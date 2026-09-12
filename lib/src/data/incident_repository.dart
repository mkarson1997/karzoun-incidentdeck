import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:incidentdeck/src/domain/incident.dart';

abstract interface class IncidentRepository {
  Future<List<Incident>> list();

  Future<Incident?> find(String id);

  Future<void> save(Incident incident);

  Future<Incident> update(
    String id,
    Incident Function(Incident current) mutation,
  );
}

class InMemoryIncidentRepository implements IncidentRepository {
  final Map<String, Incident> _incidents = <String, Incident>{};

  @override
  Future<Incident?> find(String id) async => _incidents[id];

  @override
  Future<List<Incident>> list() async {
    final incidents = _incidents.values.toList()
      ..sort((left, right) => right.updatedAt.compareTo(left.updatedAt));
    return incidents;
  }

  @override
  Future<void> save(Incident incident) async {
    _incidents[incident.id] = incident;
  }

  @override
  Future<Incident> update(
    String id,
    Incident Function(Incident current) mutation,
  ) async {
    final current = _incidents[id];
    if (current == null) {
      throw IncidentDomainException('Unknown incident: $id.');
    }
    final updated = mutation(current);
    _incidents[id] = updated;
    return updated;
  }
}

class IncidentStoreException implements Exception {
  const IncidentStoreException(this.message);

  final String message;

  @override
  String toString() => 'IncidentStoreException: $message';
}

class JsonIncidentRepository implements IncidentRepository {
  JsonIncidentRepository(this.file);

  static const int schemaVersion = 1;

  final File file;
  Future<void> _writeTail = Future<void>.value();

  @override
  Future<Incident?> find(String id) async {
    await _writeTail;
    final incidents = await _load();
    return incidents[id];
  }

  @override
  Future<List<Incident>> list() async {
    await _writeTail;
    final incidents = (await _load()).values.toList()
      ..sort((left, right) => right.updatedAt.compareTo(left.updatedAt));
    return incidents;
  }

  @override
  Future<void> save(Incident incident) async {
    final previous = _writeTail;
    final completer = Completer<void>();
    _writeTail = completer.future;

    await previous;
    try {
      final incidents = await _load();
      incidents[incident.id] = incident;
      await _write(incidents.values.toList());
    } finally {
      completer.complete();
    }
  }

  @override
  Future<Incident> update(
    String id,
    Incident Function(Incident current) mutation,
  ) async {
    final previous = _writeTail;
    final completer = Completer<void>();
    _writeTail = completer.future;

    await previous;
    try {
      final incidents = await _load();
      final current = incidents[id];
      if (current == null) {
        throw IncidentDomainException('Unknown incident: $id.');
      }
      final updated = mutation(current);
      incidents[id] = updated;
      await _write(incidents.values.toList());
      return updated;
    } finally {
      completer.complete();
    }
  }

  Future<Map<String, Incident>> _load() async {
    if (!await file.exists()) {
      return <String, Incident>{};
    }

    final raw = await file.readAsString();
    final decoded = jsonDecode(raw);
    if (decoded is! Map<String, dynamic>) {
      throw const IncidentStoreException('Root JSON value must be an object.');
    }
    if (decoded['schemaVersion'] != schemaVersion) {
      throw IncidentStoreException(
        'Unsupported schema version: ${decoded['schemaVersion']}.',
      );
    }

    final values = decoded['incidents'];
    if (values is! List) {
      throw const IncidentStoreException('incidents must be a JSON array.');
    }

    final incidents = <String, Incident>{};
    for (final value in values) {
      if (value is! Map) {
        throw const IncidentStoreException('Incident entry must be an object.');
      }
      final incident = Incident.fromJson(Map<String, Object?>.from(value));
      incidents[incident.id] = incident;
    }
    return incidents;
  }

  Future<void> _write(List<Incident> incidents) async {
    await file.parent.create(recursive: true);
    final sorted = <Incident>[...incidents]
      ..sort((left, right) => left.id.compareTo(right.id));
    final snapshot = <String, Object?>{
      'schemaVersion': schemaVersion,
      'incidents': sorted.map((incident) => incident.toJson()).toList(),
    };
    final encoded = const JsonEncoder.withIndent('  ').convert(snapshot);
    final temp = File('${file.path}.tmp');
    await temp.writeAsString(encoded, flush: true);

    try {
      await temp.rename(file.path);
    } on FileSystemException {
      if (await file.exists()) {
        await file.delete();
      }
      await temp.rename(file.path);
    }
  }
}
