import 'package:flutter_test/flutter_test.dart';
import 'package:incidentdeck/src/application/incident_service.dart';
import 'package:incidentdeck/src/data/incident_repository.dart';
import 'package:incidentdeck/src/data/incident_snapshot_codec.dart';
import 'package:incidentdeck/src/domain/incident.dart';

void main() {
  test('service exports and imports a deterministic local snapshot', () async {
    final source = IncidentService(
      repository: InMemoryIncidentRepository(),
      clock: () => DateTime.utc(2026, 9, 12, 13),
      idGenerator: (_) => 'inc-exported',
    );
    await source.declareIncident(
      title: 'Export me',
      summary: 'Local transfer',
      severity: IncidentSeverity.sev2,
    );

    final exported = await source.exportSnapshot();
    final destination = IncidentService(
      repository: InMemoryIncidentRepository(),
    );
    final imported = await destination.importSnapshot(exported);

    expect(imported, hasLength(1));
    expect(imported.single.id, 'inc-exported');
    expect(await destination.exportSnapshot(), exported);
  });

  test('invalid import never replaces existing repository contents', () async {
    final repository = InMemoryIncidentRepository();
    final service = IncidentService(
      repository: repository,
      clock: () => DateTime.utc(2026, 9, 12, 13),
      idGenerator: (_) => 'inc-existing',
    );
    await service.declareIncident(
      title: 'Keep me',
      summary: '',
      severity: IncidentSeverity.sev3,
    );

    await expectLater(
      service.importSnapshot('{"schemaVersion":99,"incidents":[]}'),
      throwsA(isA<IncidentSnapshotException>()),
    );

    final remaining = await service.listIncidents();
    expect(remaining.single.id, 'inc-existing');
  });
}
