import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:incidentdeck/src/application/incident_service.dart';
import 'package:incidentdeck/src/data/incident_repository.dart';
import 'package:incidentdeck/src/domain/incident.dart';

void main() {
  test(
    'service persists deterministic declaration and lifecycle changes',
    () async {
      final repository = InMemoryIncidentRepository();
      final times = <DateTime>[
        DateTime.utc(2026, 9, 12, 10),
        DateTime.utc(2026, 9, 12, 10, 1),
      ];
      var clockIndex = 0;
      final service = IncidentService(
        repository: repository,
        clock: () => times[clockIndex++],
        idGenerator: (_) => 'inc-deterministic',
      );

      final created = await service.declareIncident(
        title: 'Checkout unavailable',
        summary: 'Requests return 503',
        severity: IncidentSeverity.sev1,
      );
      final acknowledged = await service.transition(
        created.id,
        IncidentStatus.acknowledged,
      );

      expect(created.id, 'inc-deterministic');
      expect(acknowledged.status, IncidentStatus.acknowledged);
      expect((await service.listIncidents()).single.revision, 2);
    },
  );

  test('concurrent commands do not lose incident mutations', () async {
    final directory = await Directory.systemTemp.createTemp(
      'incidentdeck-service-',
    );
    addTearDown(() => directory.delete(recursive: true));

    final repository = JsonIncidentRepository(
      File('${directory.path}/incidents.json'),
    );
    final service = IncidentService(
      repository: repository,
      clock: () => DateTime.utc(2026, 9, 12, 11),
      idGenerator: (_) => 'inc-concurrent',
    );

    final incident = await service.declareIncident(
      title: 'Concurrent response',
      summary: 'Two responders join at once',
      severity: IncidentSeverity.sev2,
    );

    await Future.wait(<Future<Incident>>[
      service.assignResponder(incident.id, 'responder-a'),
      service.assignResponder(incident.id, 'responder-b'),
    ]);

    final restored = await service.getIncident(incident.id);
    expect(restored, isNotNull);
    expect(restored!.responders, containsAll(<String>['responder-a', 'responder-b']));
    expect(restored.responders, hasLength(2));
    expect(restored.revision, 3);
    expect(restored.timeline, hasLength(3));
  });
}
