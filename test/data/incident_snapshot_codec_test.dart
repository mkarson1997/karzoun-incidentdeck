import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:incidentdeck/src/data/incident_snapshot_codec.dart';
import 'package:incidentdeck/src/domain/incident.dart';

void main() {
  const codec = IncidentSnapshotCodec();

  test('snapshot export is deterministic and round-trips incidents', () {
    final now = DateTime.utc(2026, 9, 12, 12);
    final second = Incident.create(
      id: 'inc-b',
      title: 'Second incident',
      summary: 'B',
      severity: IncidentSeverity.sev2,
      now: now,
    );
    final first = Incident.create(
      id: 'inc-a',
      title: 'First incident',
      summary: 'A',
      severity: IncidentSeverity.sev1,
      now: now,
    );

    final encoded = codec.encode(<Incident>[second, first]);
    final decoded = codec.decode(encoded);

    expect(decoded.map((incident) => incident.id), <String>['inc-a', 'inc-b']);
    expect(codec.encode(decoded), encoded);
  });

  test('duplicate incident ids are rejected before import', () {
    final incident = Incident.create(
      id: 'inc-duplicate',
      title: 'Duplicate',
      summary: '',
      severity: IncidentSeverity.sev3,
      now: DateTime.utc(2026, 9, 12, 12),
    );
    final raw = jsonEncode(<String, Object?>{
      'schemaVersion': IncidentSnapshotCodec.schemaVersion,
      'incidents': <Object?>[incident.toJson(), incident.toJson()],
    });

    expect(
      () => codec.decode(raw),
      throwsA(isA<IncidentSnapshotException>()),
    );
  });

  test('unsupported schema is rejected', () {
    expect(
      () => codec.decode('{"schemaVersion":99,"incidents":[]}'),
      throwsA(isA<IncidentSnapshotException>()),
    );
  });
}
