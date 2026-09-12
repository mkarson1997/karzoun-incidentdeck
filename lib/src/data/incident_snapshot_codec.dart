import 'dart:convert';

import 'package:incidentdeck/src/domain/incident.dart';

class IncidentSnapshotException implements Exception {
  const IncidentSnapshotException(this.message);

  final String message;

  @override
  String toString() => 'IncidentSnapshotException: $message';
}

class IncidentSnapshotCodec {
  const IncidentSnapshotCodec();

  static const int schemaVersion = 1;

  String encode(Iterable<Incident> incidents) {
    final sorted = <Incident>[...incidents]
      ..sort((left, right) => left.id.compareTo(right.id));
    final snapshot = <String, Object?>{
      'schemaVersion': schemaVersion,
      'incidents': sorted.map((incident) => incident.toJson()).toList(),
    };
    return const JsonEncoder.withIndent('  ').convert(snapshot);
  }

  List<Incident> decode(String raw) {
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) {
        throw const IncidentSnapshotException(
          'Root JSON value must be an object.',
        );
      }
      if (decoded['schemaVersion'] != schemaVersion) {
        throw IncidentSnapshotException(
          'Unsupported schema version: ${decoded['schemaVersion']}.',
        );
      }

      final values = decoded['incidents'];
      if (values is! List) {
        throw const IncidentSnapshotException(
          'incidents must be a JSON array.',
        );
      }

      final ids = <String>{};
      final incidents = <Incident>[];
      for (final value in values) {
        if (value is! Map) {
          throw const IncidentSnapshotException(
            'Incident entry must be an object.',
          );
        }
        final incident = Incident.fromJson(Map<String, Object?>.from(value));
        _validateIncident(incident);
        if (!ids.add(incident.id)) {
          throw IncidentSnapshotException(
            'Duplicate incident id: ${incident.id}.',
          );
        }
        incidents.add(incident);
      }

      incidents.sort((left, right) => left.id.compareTo(right.id));
      return List<Incident>.unmodifiable(incidents);
    } on IncidentSnapshotException {
      rethrow;
    } on Object catch (error) {
      throw IncidentSnapshotException('Invalid incident snapshot: $error');
    }
  }

  void _validateIncident(Incident incident) {
    if (incident.id.trim().isEmpty) {
      throw const IncidentSnapshotException('Incident id must not be empty.');
    }
    if (incident.title.trim().isEmpty) {
      throw const IncidentSnapshotException(
        'Incident title must not be empty.',
      );
    }
    if (incident.revision < 1) {
      throw IncidentSnapshotException(
        'Incident ${incident.id} has an invalid revision.',
      );
    }
    if (incident.updatedAt.isBefore(incident.createdAt)) {
      throw IncidentSnapshotException(
        'Incident ${incident.id} was updated before it was created.',
      );
    }
    if (incident.timeline.isEmpty) {
      throw IncidentSnapshotException(
        'Incident ${incident.id} must contain a timeline.',
      );
    }

    final responders = <String>{};
    for (final responder in incident.responders) {
      if (responder.trim().isEmpty || !responders.add(responder)) {
        throw IncidentSnapshotException(
          'Incident ${incident.id} contains invalid responders.',
        );
      }
    }

    final alertIds = <String>{};
    for (final alert in incident.alerts) {
      if (alert.id.trim().isEmpty || !alertIds.add(alert.id)) {
        throw IncidentSnapshotException(
          'Incident ${incident.id} contains invalid alert ids.',
        );
      }
      if (alert.message.trim().isEmpty) {
        throw IncidentSnapshotException(
          'Incident ${incident.id} contains an empty alert message.',
        );
      }
      final acknowledgedAt = alert.acknowledgedAt;
      if (acknowledgedAt != null && acknowledgedAt.isBefore(alert.raisedAt)) {
        throw IncidentSnapshotException(
          'Incident ${incident.id} contains an invalid alert timestamp.',
        );
      }
    }
  }
}
