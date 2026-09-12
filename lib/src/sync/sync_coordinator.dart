import 'dart:async';
import 'dart:convert';

import 'package:incidentdeck/src/data/incident_repository.dart';
import 'package:incidentdeck/src/domain/incident.dart';
import 'package:incidentdeck/src/sync/sync_outbox.dart';
import 'package:incidentdeck/src/sync/sync_protocol.dart';
import 'package:incidentdeck/src/sync/sync_transport.dart';

class SyncCoordinator {
  SyncCoordinator({
    required this.repository,
    required this.outbox,
    required this.transport,
  });

  final IncidentRepository repository;
  final SyncOutbox outbox;
  final SyncTransport transport;
  Future<void> _syncTail = Future<void>.value();

  Future<SyncCycleResult> synchronize() async {
    final previous = _syncTail;
    final completer = Completer<void>();
    _syncTail = completer.future;

    await previous;
    try {
      return await _synchronizeOnce();
    } finally {
      completer.complete();
    }
  }

  Future<SyncCycleResult> _synchronizeOnce() async {
    final pushedOperationIds = <String>[];
    final pushConflicts = <SyncPushResult>[];
    final blockedIncidentIds = <String>{};

    final queuedOperations = await outbox.pending();
    for (final operation in queuedOperations) {
      if (blockedIncidentIds.contains(operation.incident.id)) {
        continue;
      }

      SyncPushResult pushResult;
      try {
        pushResult = await transport.push(operation);
      } on Object {
        return _result(
          pushedOperationIds: pushedOperationIds,
          pushConflicts: pushConflicts,
          transportError: 'Push failed for ${operation.operationId}.',
        );
      }

      if (pushResult.operationId != operation.operationId) {
        return _result(
          pushedOperationIds: pushedOperationIds,
          pushConflicts: pushConflicts,
          transportError:
              'Transport returned operation ${pushResult.operationId} for '
              '${operation.operationId}.',
        );
      }

      switch (pushResult.status) {
        case SyncPushStatus.accepted:
          await outbox.acknowledge(operation.operationId);
          pushedOperationIds.add(operation.operationId);
          break;
        case SyncPushStatus.conflict:
          pushConflicts.add(pushResult);
          blockedIncidentIds.add(operation.incident.id);
          break;
      }
    }

    List<Incident> remoteIncidents;
    try {
      remoteIncidents = await transport.pull();
    } on Object {
      return _result(
        pushedOperationIds: pushedOperationIds,
        pushConflicts: pushConflicts,
        transportError: 'Pull failed.',
      );
    }

    final orderedRemoteIncidents = <Incident>[...remoteIncidents]
      ..sort((left, right) {
        final idComparison = left.id.compareTo(right.id);
        if (idComparison != 0) {
          return idComparison;
        }
        return left.revision.compareTo(right.revision);
      });

    final remoteResults = <RemoteApplyResult>[];
    for (final remote in orderedRemoteIncidents) {
      final local = await repository.find(remote.id);

      if (await _hasPendingLocalWork(remote.id)) {
        remoteResults.add(
          RemoteApplyResult(
            incidentId: remote.id,
            status: RemoteApplyStatus.conflict,
            localIncident: local,
            remoteIncident: remote,
          ),
        );
        continue;
      }

      remoteResults.add(await _applyRemote(local: local, remote: remote));
    }

    return SyncCycleResult(
      pushedOperationIds: List<String>.unmodifiable(pushedOperationIds),
      pushConflicts: List<SyncPushResult>.unmodifiable(pushConflicts),
      remoteResults: List<RemoteApplyResult>.unmodifiable(remoteResults),
    );
  }

  Future<bool> _hasPendingLocalWork(String incidentId) async {
    final pendingOperations = await outbox.pending();
    return pendingOperations.any(
      (operation) => operation.incident.id == incidentId,
    );
  }

  Future<RemoteApplyResult> _applyRemote({
    required Incident? local,
    required Incident remote,
  }) async {
    if (local == null) {
      final applied = await repository.saveIfRevision(
        id: remote.id,
        expectedRevision: null,
        incident: remote,
      );
      if (applied) {
        return RemoteApplyResult(
          incidentId: remote.id,
          status: RemoteApplyStatus.applied,
          remoteIncident: remote,
        );
      }
      return _concurrentApplyConflict(remote);
    }

    if (remote.revision > local.revision) {
      final applied = await repository.saveIfRevision(
        id: remote.id,
        expectedRevision: local.revision,
        incident: remote,
      );
      if (applied) {
        return RemoteApplyResult(
          incidentId: remote.id,
          status: RemoteApplyStatus.applied,
          localIncident: local,
          remoteIncident: remote,
        );
      }
      return _concurrentApplyConflict(remote);
    }

    if (remote.revision < local.revision) {
      return RemoteApplyResult(
        incidentId: remote.id,
        status: RemoteApplyStatus.staleRemote,
        localIncident: local,
        remoteIncident: remote,
      );
    }

    if (_sameState(local, remote)) {
      return RemoteApplyResult(
        incidentId: remote.id,
        status: RemoteApplyStatus.unchanged,
        localIncident: local,
        remoteIncident: remote,
      );
    }

    return RemoteApplyResult(
      incidentId: remote.id,
      status: RemoteApplyStatus.conflict,
      localIncident: local,
      remoteIncident: remote,
    );
  }

  Future<RemoteApplyResult> _concurrentApplyConflict(Incident remote) async {
    final current = await repository.find(remote.id);
    return RemoteApplyResult(
      incidentId: remote.id,
      status: RemoteApplyStatus.conflict,
      localIncident: current,
      remoteIncident: remote,
    );
  }

  SyncCycleResult _result({
    required List<String> pushedOperationIds,
    required List<SyncPushResult> pushConflicts,
    required String transportError,
  }) {
    return SyncCycleResult(
      pushedOperationIds: List<String>.unmodifiable(pushedOperationIds),
      pushConflicts: List<SyncPushResult>.unmodifiable(pushConflicts),
      remoteResults: const <RemoteApplyResult>[],
      transportError: transportError,
    );
  }

  bool _sameState(Incident left, Incident right) {
    return jsonEncode(left.toJson()) == jsonEncode(right.toJson());
  }
}
