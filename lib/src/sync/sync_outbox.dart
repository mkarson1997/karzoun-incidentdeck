import 'dart:convert';

import 'package:incidentdeck/src/sync/sync_protocol.dart';

abstract interface class SyncOutbox {
  Future<void> enqueue(SyncOperation operation);

  Future<List<SyncOperation>> pending();

  Future<void> acknowledge(String operationId);
}

class SyncOutboxException implements Exception {
  const SyncOutboxException(this.message);

  final String message;

  @override
  String toString() => 'SyncOutboxException: $message';
}

class InMemorySyncOutbox implements SyncOutbox {
  final Map<String, SyncOperation> _operations = <String, SyncOperation>{};
  final Map<String, SyncOperation> _acknowledgedOperations =
      <String, SyncOperation>{};

  @override
  Future<void> enqueue(SyncOperation operation) async {
    final expectedOperationId = SyncOperation.stableOperationId(
      incidentId: operation.incident.id,
      baseRevision: operation.baseRevision,
      targetRevision: operation.targetRevision,
    );
    if (operation.operationId != expectedOperationId) {
      throw SyncOutboxException(
        'Operation id does not match its deterministic revision identity: '
        '${operation.operationId}.',
      );
    }

    final acknowledged = _acknowledgedOperations[operation.operationId];
    if (acknowledged != null) {
      _requireSamePayload(acknowledged, operation);
      return;
    }

    final existing = _operations[operation.operationId];
    if (existing == null) {
      _operations[operation.operationId] = operation;
      return;
    }

    _requireSamePayload(existing, operation);
  }

  @override
  Future<List<SyncOperation>> pending() async {
    final operations = _operations.values.toList()
      ..sort((left, right) {
        final timeComparison = left.enqueuedAt.toUtc().compareTo(
          right.enqueuedAt.toUtc(),
        );
        if (timeComparison != 0) {
          return timeComparison;
        }

        final incidentComparison = left.incident.id.compareTo(right.incident.id);
        if (incidentComparison != 0) {
          return incidentComparison;
        }

        final baseRevisionComparison = left.baseRevision.compareTo(
          right.baseRevision,
        );
        if (baseRevisionComparison != 0) {
          return baseRevisionComparison;
        }

        final targetRevisionComparison = left.targetRevision.compareTo(
          right.targetRevision,
        );
        if (targetRevisionComparison != 0) {
          return targetRevisionComparison;
        }

        return left.operationId.compareTo(right.operationId);
      });
    return List<SyncOperation>.unmodifiable(operations);
  }

  @override
  Future<void> acknowledge(String operationId) async {
    final operation = _operations.remove(operationId);
    if (operation != null) {
      _acknowledgedOperations[operationId] = operation;
    }
  }

  void _requireSamePayload(SyncOperation left, SyncOperation right) {
    if (!_samePayload(left, right)) {
      throw SyncOutboxException(
        'Operation id collision with different payload: ${right.operationId}.',
      );
    }
  }

  bool _samePayload(SyncOperation left, SyncOperation right) {
    return left.baseRevision == right.baseRevision &&
        left.targetRevision == right.targetRevision &&
        jsonEncode(left.incident.toJson()) ==
            jsonEncode(right.incident.toJson());
  }
}
