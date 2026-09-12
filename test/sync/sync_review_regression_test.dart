import 'package:flutter_test/flutter_test.dart';
import 'package:incidentdeck/src/data/incident_repository.dart';
import 'package:incidentdeck/src/domain/incident.dart';
import 'package:incidentdeck/src/sync/sync_coordinator.dart';
import 'package:incidentdeck/src/sync/sync_outbox.dart';
import 'package:incidentdeck/src/sync/sync_protocol.dart';
import 'package:incidentdeck/src/sync/sync_transport.dart';

void main() {
  test('same-time operations use numeric revision order for one incident', () async {
    final outbox = InMemorySyncOutbox();
    final revision10 = _incidentAtRevision('incident-revision-order', 10);
    final revision11 = revision10.addNote(
      'Revision 11',
      DateTime.utc(2026, 9, 12, 16, 11),
    );
    final enqueuedAt = DateTime.utc(2026, 9, 12, 17);
    final operation10 = SyncOperation.forIncident(
      incident: revision10,
      baseRevision: 9,
      enqueuedAt: enqueuedAt,
    );
    final operation11 = SyncOperation.forIncident(
      incident: revision11,
      baseRevision: 10,
      enqueuedAt: enqueuedAt,
    );

    await outbox.enqueue(operation11);
    await outbox.enqueue(operation10);

    final pending = await outbox.pending();

    expect(
      pending.map((operation) => operation.targetRevision),
      <int>[10, 11],
    );
  });

  test('fresh pending work check blocks remote apply after local read', () async {
    final outbox = InMemorySyncOutbox();
    final local = _incidentAtRevision('incident-late-pending', 1);
    final pendingLocal = local.addNote(
      'Pending local note',
      DateTime.utc(2026, 9, 12, 16),
    );
    final remote = local.addNote(
      'Remote note',
      DateTime.utc(2026, 9, 12, 16, 30),
    );
    final operation = SyncOperation.forIncident(
      incident: pendingLocal,
      baseRevision: 1,
      enqueuedAt: DateTime.utc(2026, 9, 12, 16),
    );
    final repository = _EnqueueOnFindRepository(outbox, operation);
    await repository.save(local);

    final coordinator = SyncCoordinator(
      repository: repository,
      outbox: outbox,
      transport: _RemoteOnlyTransport(remote),
    );

    final result = await coordinator.synchronize();
    final stored = await repository.find(local.id);

    expect(result.remoteResults.single.status, RemoteApplyStatus.conflict);
    expect(stored?.revision, 1);
    expect(await outbox.pending(), hasLength(1));
  });
}

Incident _incidentAtRevision(String id, int targetRevision) {
  var incident = Incident.create(
    id: id,
    title: 'Incident $id',
    summary: 'Summary',
    severity: IncidentSeverity.sev2,
    now: DateTime.utc(2026, 9, 12, 15),
  );
  for (var revision = 2; revision <= targetRevision; revision += 1) {
    incident = incident.addNote(
      'Revision $revision',
      DateTime.utc(2026, 9, 12, 15).add(Duration(minutes: revision)),
    );
  }
  return incident;
}

class _RemoteOnlyTransport implements SyncTransport {
  const _RemoteOnlyTransport(this.remote);

  final Incident remote;

  @override
  Future<SyncPushResult> push(SyncOperation operation) {
    throw StateError('No push expected in this test.');
  }

  @override
  Future<List<Incident>> pull() async => <Incident>[remote];
}

class _EnqueueOnFindRepository extends InMemoryIncidentRepository {
  _EnqueueOnFindRepository(this.outbox, this.operation);

  final SyncOutbox outbox;
  final SyncOperation operation;
  bool _enqueued = false;

  @override
  Future<Incident?> find(String id) async {
    final incident = await super.find(id);
    if (!_enqueued) {
      _enqueued = true;
      await outbox.enqueue(operation);
    }
    return incident;
  }
}
