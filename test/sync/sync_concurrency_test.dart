import 'package:flutter_test/flutter_test.dart';
import 'package:incidentdeck/src/data/incident_repository.dart';
import 'package:incidentdeck/src/domain/incident.dart';
import 'package:incidentdeck/src/sync/sync_coordinator.dart';
import 'package:incidentdeck/src/sync/sync_outbox.dart';
import 'package:incidentdeck/src/sync/sync_protocol.dart';
import 'package:incidentdeck/src/sync/sync_transport.dart';

void main() {
  test(
    'concurrent sync cycles serialize and push a pending operation once',
    () async {
      final outbox = InMemorySyncOutbox();
      final operation = _operation(_incident(id: 'incident-concurrent-sync'));
      await outbox.enqueue(operation);

      final transport = _DelayedTransport();
      final coordinator = SyncCoordinator(
        repository: InMemoryIncidentRepository(),
        outbox: outbox,
        transport: transport,
      );

      await Future.wait(<Future<SyncCycleResult>>[
        coordinator.synchronize(),
        coordinator.synchronize(),
      ]);

      expect(transport.pushedOperationIds, <String>[operation.operationId]);
      expect(await outbox.pending(), isEmpty);
    },
  );

  test('accepted operation cannot be re-enqueued in the same outbox', () async {
    final outbox = InMemorySyncOutbox();
    final operation = _operation(_incident(id: 'incident-accepted-replay'));

    await outbox.enqueue(operation);
    await outbox.acknowledge(operation.operationId);
    await outbox.enqueue(operation);

    expect(await outbox.pending(), isEmpty);
  });

  test('remote apply does not overwrite a racing local mutation', () async {
    final local = _incident(id: 'incident-apply-race');
    final remote = local.addNote('Remote note', DateTime.utc(2026, 9, 12, 16));
    final repository = _RacingIncidentRepository(local);
    final transport = _PullOnlyTransport(remote);
    final coordinator = SyncCoordinator(
      repository: repository,
      outbox: InMemorySyncOutbox(),
      transport: transport,
    );

    final result = await coordinator.synchronize();
    final stored = await repository.find(local.id);

    expect(result.remoteResults.single.status, RemoteApplyStatus.conflict);
    expect(stored, isNotNull);
    expect(stored!.revision, 2);
    expect(stored.timeline.last.message, 'Local racing mutation');
  });
}

Incident _incident({required String id}) {
  return Incident.create(
    id: id,
    title: 'Incident $id',
    summary: 'Summary',
    severity: IncidentSeverity.sev2,
    now: DateTime.utc(2026, 9, 12, 15),
  );
}

SyncOperation _operation(Incident incident) {
  return SyncOperation.forIncident(
    incident: incident,
    baseRevision: incident.revision - 1,
    enqueuedAt: DateTime.utc(2026, 9, 12, 15),
  );
}

class _DelayedTransport implements SyncTransport {
  final List<String> pushedOperationIds = <String>[];

  @override
  Future<SyncPushResult> push(SyncOperation operation) async {
    pushedOperationIds.add(operation.operationId);
    await Future<void>.delayed(const Duration(milliseconds: 10));
    return SyncPushResult(
      operationId: operation.operationId,
      status: SyncPushStatus.accepted,
    );
  }

  @override
  Future<List<Incident>> pull() async => const <Incident>[];
}

class _PullOnlyTransport implements SyncTransport {
  const _PullOnlyTransport(this.remote);

  final Incident remote;

  @override
  Future<SyncPushResult> push(SyncOperation operation) {
    throw StateError('No push expected in this test.');
  }

  @override
  Future<List<Incident>> pull() async => <Incident>[remote];
}

class _RacingIncidentRepository implements IncidentRepository {
  _RacingIncidentRepository(Incident initial) {
    _incidents[initial.id] = initial;
  }

  final Map<String, Incident> _incidents = <String, Incident>{};
  bool _injectRace = true;

  @override
  Future<Incident?> find(String id) async => _incidents[id];

  @override
  Future<List<Incident>> list() async => _incidents.values.toList();

  @override
  Future<void> save(Incident incident) async {
    _incidents[incident.id] = incident;
  }

  @override
  Future<bool> saveIfRevision({
    required String id,
    required int? expectedRevision,
    required Incident incident,
  }) async {
    if (_injectRace) {
      _injectRace = false;
      final current = _incidents[id]!;
      _incidents[id] = current.addNote(
        'Local racing mutation',
        DateTime.utc(2026, 9, 12, 16, 30),
      );
    }

    final current = _incidents[id];
    if (current?.revision != expectedRevision) {
      return false;
    }
    _incidents[id] = incident;
    return true;
  }

  @override
  Future<Incident> update(
    String id,
    Incident Function(Incident current) mutation,
  ) async {
    final updated = mutation(_incidents[id]!);
    _incidents[id] = updated;
    return updated;
  }

  @override
  Future<void> replaceAll(Iterable<Incident> incidents) async {
    _incidents
      ..clear()
      ..addEntries(
        incidents.map((incident) => MapEntry(incident.id, incident)),
      );
  }
}
