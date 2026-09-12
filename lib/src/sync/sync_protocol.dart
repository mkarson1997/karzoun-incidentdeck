import 'package:incidentdeck/src/domain/incident.dart';

enum SyncPushStatus { accepted, conflict }

enum RemoteApplyStatus { applied, unchanged, staleRemote, conflict }

class SyncOperation {
  const SyncOperation({
    required this.operationId,
    required this.incident,
    required this.baseRevision,
    required this.enqueuedAt,
  });

  final String operationId;
  final Incident incident;
  final int baseRevision;
  final DateTime enqueuedAt;

  int get targetRevision => incident.revision;

  Map<String, Object?> toJson() => <String, Object?>{
    'operationId': operationId,
    'incidentId': incident.id,
    'baseRevision': baseRevision,
    'targetRevision': targetRevision,
    'enqueuedAt': enqueuedAt.toUtc().toIso8601String(),
    'incident': incident.toJson(),
  };
}

class SyncPushResult {
  const SyncPushResult({
    required this.operationId,
    required this.status,
    this.remoteIncident,
  });

  final String operationId;
  final SyncPushStatus status;
  final Incident? remoteIncident;
}

class RemoteApplyResult {
  const RemoteApplyResult({
    required this.incidentId,
    required this.status,
    this.localIncident,
    this.remoteIncident,
  });

  final String incidentId;
  final RemoteApplyStatus status;
  final Incident? localIncident;
  final Incident? remoteIncident;
}

class SyncCycleResult {
  const SyncCycleResult({
    required this.pushedOperationIds,
    required this.pushConflicts,
    required this.remoteResults,
  });

  final List<String> pushedOperationIds;
  final List<SyncPushResult> pushConflicts;
  final List<RemoteApplyResult> remoteResults;
}
