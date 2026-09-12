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

    final existing = _operations[operation.operationId];
    if (existing == null) {
      _operations[operation.operationId] = operation;
      return;
    }

    if (!_samePayload(existing, operation)) {
      throw SyncOutboxException(
        'Operation id collision with different payload: '
        '${operation.operationId}.',
      );
    }
  }

  @override
  Future<List<SyncOperation>> pending() async {
    final operations = _operations.values.toList()
      ..sort((left, right) {
        final timeComparison = left.enqueuedAt
            .toUtc()
            .compareTo(right.enqueuedAt.toUtc());
        if (timeComparison != 0) {
          return timeComparison;
        }
        return left.operationId.compareTo(right.operationId);
      });
    return List<SyncOperation>.unmodifiable(operations);
  }

  @override
  Future<void> acknowledge(String operationId) async {
    _operations.remove(operationId);
  }

  bool _samePayload(SyncOperation left, SyncOperation right) {
    return left.baseRevision == right.baseRevision &&
        left.targetRevision == right.targetRevision &&
        jsonEncode(left.incident.toJson()) == jsonEncode(right.incident.toJson());
  }
}
