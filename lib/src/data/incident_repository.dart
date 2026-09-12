import 'dart:async';
import 'dart:io';

import 'package:incidentdeck/src/data/incident_snapshot_codec.dart';
import 'package:incidentdeck/src/domain/incident.dart';

abstract interface class IncidentRepository {
  Future<List<Incident>> list();

  Future<Incident?> find(String id);

  Future<void> save(Incident incident);

  Future<Incident> update(
    String id,
    Incident Function(Incident current) mutation,
  );

  Future<void> replaceAll(Iterable<Incident> incidents);
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

  @override
  Future<void> replaceAll(Iterable<Incident> incidents) async {
    _incidents
      ..clear()
      ..addEntries(
        incidents.map((incident) => MapEntry(incident.id, incident)),
      );
  }
}

class IncidentStoreException implements Exception {
  const IncidentStoreException(this.message);

  final String message;

  @override
  String toString() => 'IncidentStoreException: $message';
}

class JsonIncidentRepository implements IncidentRepository {
  JsonIncidentRepository(
    this.file, {
    IncidentSnapshotCodec codec = const IncidentSnapshotCodec(),
  }) : _codec = codec;

  final File file;
  final IncidentSnapshotCodec _codec;
  Future<void> _writeTail = Future<void>.value();

  File get backupFile => File('${file.path}.bak');
  File get temporaryFile => File('${file.path}.tmp');
  File get corruptFile => File('${file.path}.corrupt');

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
  Future<void> save(Incident incident) {
    return _serialized<void>(() async {
      final incidents = await _load();
      incidents[incident.id] = incident;
      await _write(incidents.values);
    });
  }

  @override
  Future<Incident> update(
    String id,
    Incident Function(Incident current) mutation,
  ) {
    return _serialized<Incident>(() async {
      final incidents = await _load();
      final current = incidents[id];
      if (current == null) {
        throw IncidentDomainException('Unknown incident: $id.');
      }
      final updated = mutation(current);
      incidents[id] = updated;
      await _write(incidents.values);
      return updated;
    });
  }

  @override
  Future<void> replaceAll(Iterable<Incident> incidents) {
    final replacement = <Incident>[...incidents];
    return _serialized<void>(() => _write(replacement));
  }

  Future<T> _serialized<T>(Future<T> Function() action) async {
    final previous = _writeTail;
    final completer = Completer<void>();
    _writeTail = completer.future;

    await previous;
    try {
      return await action();
    } finally {
      completer.complete();
    }
  }

  Future<Map<String, Incident>> _load() async {
    if (!await file.exists()) {
      final recovered = await _recoverMissingPrimary();
      if (recovered != null) {
        return recovered;
      }
      return <String, Incident>{};
    }

    try {
      final incidents = await _read(file);
      await _deleteIfExists(temporaryFile);
      return incidents;
    } on IncidentStoreException catch (primaryError) {
      if (!await backupFile.exists()) {
        throw IncidentStoreException(
          'Primary incident snapshot is invalid and no backup is available: '
          '$primaryError',
        );
      }

      try {
        final backup = await _read(backupFile);
        await _restoreBackupOverInvalidPrimary();
        return backup;
      } on IncidentStoreException catch (backupError) {
        throw IncidentStoreException(
          'Primary and backup incident snapshots are invalid. '
          'Primary: $primaryError Backup: $backupError',
        );
      }
    }
  }

  Future<Map<String, Incident>?> _recoverMissingPrimary() async {
    if (await temporaryFile.exists()) {
      try {
        final pending = await _read(temporaryFile);
        await file.parent.create(recursive: true);
        await temporaryFile.rename(file.path);
        await _deleteIfExists(backupFile);
        return pending;
      } on IncidentStoreException {
        await _deleteIfExists(temporaryFile);
      }
    }

    if (await backupFile.exists()) {
      final backup = await _read(backupFile);
      await file.parent.create(recursive: true);
      await backupFile.copy(file.path);
      return backup;
    }

    return null;
  }

  Future<Map<String, Incident>> _read(File source) async {
    try {
      final incidents = _codec.decode(await source.readAsString());
      return <String, Incident>{
        for (final incident in incidents) incident.id: incident,
      };
    } on IncidentSnapshotException catch (error) {
      throw IncidentStoreException('${source.path}: $error');
    } on FileSystemException catch (error) {
      throw IncidentStoreException('${source.path}: $error');
    }
  }

  Future<void> _write(Iterable<Incident> incidents) async {
    await file.parent.create(recursive: true);
    final encoded = _codec.encode(incidents);
    await temporaryFile.writeAsString(encoded, flush: true);

    await _deleteIfExists(backupFile);
    if (await file.exists()) {
      await file.rename(backupFile.path);
    }

    try {
      await temporaryFile.rename(file.path);
      await _deleteIfExists(backupFile);
    } on FileSystemException catch (error) {
      if (!await file.exists() && await backupFile.exists()) {
        await backupFile.rename(file.path);
      }
      throw IncidentStoreException(
        'Unable to commit incident snapshot: $error',
      );
    }
  }

  Future<void> _restoreBackupOverInvalidPrimary() async {
    await _deleteIfExists(corruptFile);
    if (await file.exists()) {
      await file.rename(corruptFile.path);
    }

    try {
      await backupFile.copy(file.path);
      await _deleteIfExists(temporaryFile);
    } on FileSystemException catch (error) {
      if (!await file.exists() && await corruptFile.exists()) {
        await corruptFile.rename(file.path);
      }
      throw IncidentStoreException('Unable to restore valid backup: $error');
    }
  }

  Future<void> _deleteIfExists(File candidate) async {
    if (await candidate.exists()) {
      await candidate.delete();
    }
  }
}
