import 'package:flutter_test/flutter_test.dart';
import 'package:incidentdeck/src/data/incident_repository.dart';
import 'package:incidentdeck/src/domain/incident.dart';
import 'package:incidentdeck/src/sync/sync_coordinator.dart';
import 'package:incidentdeck/src/sync/sync_outbox.dart';
import 'package:incidentdeck/src/sync/sync_protocol.dart';
import 'package:incidentdeck/src/sync/sync_transport.dart';

void main() {
  group('deterministic outbox', () {
    test('uses stable operation ids and deterministic replay order', () async {
      final outbox = InMemorySyncOutbox();
      final firstIncident = _incident(id: 'incident-z');
      final secondIncident = _incident(id: 'incident-a');
      final enqueuedAt = DateTime.utc(2026, 9, 12, 15);

      final first = SyncOperation.forIncident(
        incident: firstIncident,
        baseRevision: 0,
        enqueuedAt: enqueuedAt,
      );
      final repeated = SyncOperation.forIncident(
        incident: firstIncident,
        baseRevision: 0,
        enqueuedAt: enqueuedAt.add(const Duration(minutes: 5)),
      );
      final second = SyncOperation.forIncident(
        incident: secondIncident,
        baseRevision: 0,
        enqueuedAt: enqueuedAt,
      );

      expect(repeated.operationId, first.operationId);

      await outbox.enqueue(first);
      await outbox.enqueue(repeated);
      await outbox.enqueue(second);

      final transport = _FakeTransport();
      final coordinator = SyncCoordinator(
        repository: InMemoryIncidentRepository(),
        outbox: outbox,
        transport: transport,
      );

      final result = await coordinator.synchronize();

      expect(result.completed, isTrue);
      expect(transport.pushedOperationIds, <String>[
        second.operationId,
        first.operationId,
      ]);
      expect(await outbox.pending(), isEmpty);
    });

    test('duplicate acknowledgement is harmless', () async {
      final outbox = InMemorySyncOutbox();
      final operation = _operation(_incident(id: 'incident-ack'));

      await outbox.enqueue(operation);
      await outbox.acknowledge(operation.operationId);
      await outbox.acknowledge(operation.operationId);

      expect(await outbox.pending(), isEmpty);
    });
  });

  group('push behavior', () {
    test('transport failure preserves pending work for retry', () async {
      final repository = InMemoryIncidentRepository();
      final outbox = InMemorySyncOutbox();
      final operation = _operation(_incident(id: 'incident-offline'));
      await outbox.enqueue(operation);

      final transport = _FakeTransport()
        ..pushFailure = StateError('network unavailable');
      final coordinator = SyncCoordinator(
        repository: repository,
        outbox: outbox,
        transport: transport,
      );

      final failed = await coordinator.synchronize();

      expect(failed.completed, isFalse);
      expect(failed.transportError, contains('Push failed'));
      expect(
        (await outbox.pending()).single.operationId,
        operation.operationId,
      );

      transport.pushFailure = null;
      final retried = await coordinator.synchronize();

      expect(retried.completed, isTrue);
      expect(await outbox.pending(), isEmpty);
      expect(transport.pushedOperationIds, <String>[
        operation.operationId,
        operation.operationId,
      ]);
    });

    test('push conflict retains local operation', () async {
      final local = _incident(id: 'incident-conflict');
      final remote = _incident(
        id: 'incident-conflict',
        summary: 'Remote branch',
      );
      final outbox = InMemorySyncOutbox();
      final operation = _operation(local);
      await outbox.enqueue(operation);

      final transport = _FakeTransport();
      transport.pushResults[operation.operationId] = SyncPushResult(
        operationId: operation.operationId,
        status: SyncPushStatus.conflict,
        remoteIncident: remote,
      );

      final coordinator = SyncCoordinator(
        repository: InMemoryIncidentRepository(),
        outbox: outbox,
        transport: transport,
      );

      final result = await coordinator.synchronize();

      expect(result.pushConflicts, hasLength(1));
      expect(
        (await outbox.pending()).single.operationId,
        operation.operationId,
      );
    });

    test('accepted operation is not replayed on a repeated cycle', () async {
      final outbox = InMemorySyncOutbox();
      final operation = _operation(_incident(id: 'incident-once'));
      await outbox.enqueue(operation);
      final transport = _FakeTransport();
      final coordinator = SyncCoordinator(
        repository: InMemoryIncidentRepository(),
        outbox: outbox,
        transport: transport,
      );

      await coordinator.synchronize();
      await coordinator.synchronize();

      expect(transport.pushedOperationIds, <String>[operation.operationId]);
      expect(await outbox.pending(), isEmpty);
    });
  });

  group('remote revision application', () {
    test('applies a remote incident when local state is missing', () async {
      final repository = InMemoryIncidentRepository();
      final remote = _incident(id: 'incident-new-remote');
      final transport = _FakeTransport()..remoteIncidents = <Incident>[remote];
      final coordinator = SyncCoordinator(
        repository: repository,
        outbox: InMemorySyncOutbox(),
        transport: transport,
      );

      final result = await coordinator.synchronize();

      expect(result.remoteResults.single.status, RemoteApplyStatus.applied);
      expect((await repository.find(remote.id))?.revision, 1);
    });

    test('rejects a stale remote revision', () async {
      final repository = InMemoryIncidentRepository();
      final remote = _incident(id: 'incident-stale');
      final local = remote.addNote(
        'Local change',
        DateTime.utc(2026, 9, 12, 16),
      );
      await repository.save(local);

      final transport = _FakeTransport()..remoteIncidents = <Incident>[remote];
      final coordinator = SyncCoordinator(
        repository: repository,
        outbox: InMemorySyncOutbox(),
        transport: transport,
      );

      final result = await coordinator.synchronize();

      expect(result.remoteResults.single.status, RemoteApplyStatus.staleRemote);
      expect((await repository.find(local.id))?.revision, 2);
    });

    test(
      'applies a newer remote revision when no local work is pending',
      () async {
        final repository = InMemoryIncidentRepository();
        final local = _incident(id: 'incident-newer');
        final remote = local.addNote(
          'Remote mitigation detail',
          DateTime.utc(2026, 9, 12, 16),
        );
        await repository.save(local);

        final transport = _FakeTransport()
          ..remoteIncidents = <Incident>[remote];
        final coordinator = SyncCoordinator(
          repository: repository,
          outbox: InMemorySyncOutbox(),
          transport: transport,
        );

        final result = await coordinator.synchronize();

        expect(result.remoteResults.single.status, RemoteApplyStatus.applied);
        expect((await repository.find(local.id))?.revision, 2);
      },
    );

    test('equal revision and equal state is unchanged', () async {
      final repository = InMemoryIncidentRepository();
      final local = _incident(id: 'incident-equal');
      await repository.save(local);

      final transport = _FakeTransport()..remoteIncidents = <Incident>[local];
      final coordinator = SyncCoordinator(
        repository: repository,
        outbox: InMemorySyncOutbox(),
        transport: transport,
      );

      final result = await coordinator.synchronize();

      expect(result.remoteResults.single.status, RemoteApplyStatus.unchanged);
    });

    test(
      'equal revision with divergent state is an explicit conflict',
      () async {
        final repository = InMemoryIncidentRepository();
        final local = _incident(
          id: 'incident-divergent',
          summary: 'Local summary',
        );
        final remote = _incident(
          id: 'incident-divergent',
          summary: 'Remote summary',
        );
        await repository.save(local);

        final transport = _FakeTransport()
          ..remoteIncidents = <Incident>[remote];
        final coordinator = SyncCoordinator(
          repository: repository,
          outbox: InMemorySyncOutbox(),
          transport: transport,
        );

        final result = await coordinator.synchronize();

        expect(result.remoteResults.single.status, RemoteApplyStatus.conflict);
        expect((await repository.find(local.id))?.summary, 'Local summary');
      },
    );

    test('pending local work blocks a newer remote overwrite', () async {
      final repository = InMemoryIncidentRepository();
      final localBase = _incident(id: 'incident-pending');
      final local = localBase.addNote(
        'Local pending note',
        DateTime.utc(2026, 9, 12, 16),
      );
      final remote = local.addNote(
        'Remote newer note',
        DateTime.utc(2026, 9, 12, 17),
      );
      await repository.save(local);

      final outbox = InMemorySyncOutbox();
      final operation = SyncOperation.forIncident(
        incident: local,
        baseRevision: 1,
        enqueuedAt: DateTime.utc(2026, 9, 12, 16),
      );
      await outbox.enqueue(operation);

      final transport = _FakeTransport()..remoteIncidents = <Incident>[remote];
      transport.pushResults[operation.operationId] = SyncPushResult(
        operationId: operation.operationId,
        status: SyncPushStatus.conflict,
        remoteIncident: remote,
      );

      final coordinator = SyncCoordinator(
        repository: repository,
        outbox: outbox,
        transport: transport,
      );

      final result = await coordinator.synchronize();

      expect(result.pushConflicts, hasLength(1));
      expect(result.remoteResults.single.status, RemoteApplyStatus.conflict);
      expect((await repository.find(local.id))?.revision, 2);
      expect(await outbox.pending(), hasLength(1));
    });
  });
}

Incident _incident({required String id, String summary = 'Initial summary'}) {
  return Incident.create(
    id: id,
    title: 'Incident $id',
    summary: summary,
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

class _FakeTransport implements SyncTransport {
  final List<String> pushedOperationIds = <String>[];
  final Map<String, SyncPushResult> pushResults = <String, SyncPushResult>{};
  List<Incident> remoteIncidents = <Incident>[];
  Object? pushFailure;
  Object? pullFailure;

  @override
  Future<SyncPushResult> push(SyncOperation operation) async {
    pushedOperationIds.add(operation.operationId);
    final failure = pushFailure;
    if (failure != null) {
      throw failure;
    }
    return pushResults[operation.operationId] ??
        SyncPushResult(
          operationId: operation.operationId,
          status: SyncPushStatus.accepted,
        );
  }

  @override
  Future<List<Incident>> pull() async {
    final failure = pullFailure;
    if (failure != null) {
      throw failure;
    }
    return List<Incident>.unmodifiable(remoteIncidents);
  }
}
