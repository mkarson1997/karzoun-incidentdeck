import 'package:incidentdeck/src/domain/incident.dart';

enum SyncPushStatus { accepted, conflict }

enum RemoteApplyStatus { applied, unchanged, staleRemote, conflict }

class SyncProtocolException implements Exception {
  const SyncProtocolException(this.message);

  final String message;

  @override
  String toString() => 'SyncProtocolException: $message';
}

class SyncOperation {
  const SyncOperation({
    required this.operationId,
    required this.incident,
    required this.baseRevision,
    required this.enqueuedAt,
  });

  factory SyncOperation.forIncident({
    required Incident incident,
    required int baseRevision,
    required DateTime enqueuedAt,
  }) {
    if (baseRevision < 0) {
      throw const SyncProtocolException(
        'Sync base revision must not be negative.',
      );
    }
    if (incident.revision <= baseRevision) {
      throw SyncProtocolException(
        'Sync target revision ${incident.revision} must be newer than '
        'base revision $baseRevision for ${incident.id}.',
      );
    }

    return SyncOperation(
      operationId: stableOperationId(
        incidentId: incident.id,
        baseRevision: baseRevision,
        targetRevision: incident.revision,
      ),
      incident: incident,
      baseRevision: baseRevision,
      enqueuedAt: enqueuedAt.toUtc(),
    );
  }

  final String operationId;
  final Incident incident;
  final int baseRevision;
  final DateTime enqueuedAt;

  int get targetRevision => incident.revision;

  static String stableOperationId({
    required String incidentId,
    required int baseRevision,
    required int targetRevision,
  }) {
    final encodedIncidentId = Uri.encodeComponent(incidentId);
    return 'incident:$encodedIncidentId:$baseRevision:$targetRevision';
  }

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
    this.transportError,
  });

  final List<String> pushedOperationIds;
  final List<SyncPushResult> pushConflicts;
  final List<RemoteApplyResult> remoteResults;
  final String? transportError;

  bool get completed => transportError == null;
}
