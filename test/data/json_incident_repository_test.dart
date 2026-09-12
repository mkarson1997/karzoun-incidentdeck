import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:incidentdeck/src/data/incident_repository.dart';
import 'package:incidentdeck/src/data/incident_snapshot_codec.dart';
import 'package:incidentdeck/src/domain/incident.dart';

void main() {
  test('versioned JSON store survives repository restart and update', () async {
    final directory = await Directory.systemTemp.createTemp(
      'incidentdeck-test-',
    );
    addTearDown(() => directory.delete(recursive: true));
    final file = File('${directory.path}/incidentdeck.json');
    final t0 = DateTime.utc(2026, 9, 12, 9);

    final first = JsonIncidentRepository(file);
    final incident = Incident.create(
      id: 'inc-persisted',
      title: 'Worker failure',
      summary: 'Background workers stopped',
      severity: IncidentSeverity.sev2,
      now: t0,
    );
    await first.save(incident);

    final restarted = JsonIncidentRepository(file);
    final restored = await restarted.find('inc-persisted');
    expect(restored, isNotNull);
    expect(restored!.title, 'Worker failure');
    expect(restored.revision, 1);

    final acknowledged = restored.transitionTo(
      IncidentStatus.acknowledged,
      t0.add(const Duration(minutes: 5)),
    );
    await restarted.save(acknowledged);

    final third = JsonIncidentRepository(file);
    final listed = await third.list();
    expect(listed, hasLength(1));
    expect(listed.single.status, IncidentStatus.acknowledged);
    expect(listed.single.revision, 2);
  });

  test('valid backup restores a corrupted primary snapshot', () async {
    final directory = await Directory.systemTemp.createTemp(
      'incidentdeck-recovery-',
    );
    addTearDown(() => directory.delete(recursive: true));
    final file = File('${directory.path}/incidentdeck.json');
    final repository = JsonIncidentRepository(file);
    final incident = Incident.create(
      id: 'inc-recover',
      title: 'Recoverable incident',
      summary: '',
      severity: IncidentSeverity.sev2,
      now: DateTime.utc(2026, 9, 12, 10),
    );
    await repository.save(incident);
    await file.copy('${file.path}.bak');
    await file.writeAsString('{not-valid-json');

    final restarted = JsonIncidentRepository(file);
    final listed = await restarted.list();

    expect(listed.single.id, 'inc-recover');
    expect(await restarted.corruptFile.exists(), isTrue);
    expect(await file.readAsString(), contains('inc-recover'));
  });

  test('complete temporary snapshot wins after interrupted rotation', () async {
    final directory = await Directory.systemTemp.createTemp(
      'incidentdeck-interrupted-',
    );
    addTearDown(() => directory.delete(recursive: true));
    final file = File('${directory.path}/incidentdeck.json');
    final oldIncident = Incident.create(
      id: 'inc-old',
      title: 'Old snapshot',
      summary: '',
      severity: IncidentSeverity.sev3,
      now: DateTime.utc(2026, 9, 12, 10),
    );
    final newIncident = Incident.create(
      id: 'inc-new',
      title: 'Pending snapshot',
      summary: '',
      severity: IncidentSeverity.sev1,
      now: DateTime.utc(2026, 9, 12, 11),
    );
    const codec = IncidentSnapshotCodec();
    await file.parent.create(recursive: true);
    await File('${file.path}.bak').writeAsString(codec.encode(<Incident>[oldIncident]));
    await File('${file.path}.tmp').writeAsString(codec.encode(<Incident>[newIncident]));

    final repository = JsonIncidentRepository(file);
    final listed = await repository.list();

    expect(listed.single.id, 'inc-new');
    expect(await file.exists(), isTrue);
    expect(await repository.backupFile.exists(), isFalse);
  });

  test('unsupported snapshot version is rejected', () async {
    final directory = await Directory.systemTemp.createTemp(
      'incidentdeck-test-',
    );
    addTearDown(() => directory.delete(recursive: true));
    final file = File('${directory.path}/incidentdeck.json');
    await file.writeAsString('{"schemaVersion":99,"incidents":[]}');

    final repository = JsonIncidentRepository(file);
    expect(repository.list(), throwsA(isA<IncidentStoreException>()));
  });
}
