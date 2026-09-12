import 'package:flutter_test/flutter_test.dart';
import 'package:incidentdeck/src/domain/incident.dart';

void main() {
  final t0 = DateTime.utc(2026, 9, 12, 8);

  test('incident lifecycle rejects invalid transitions', () {
    final incident = Incident.create(
      id: 'inc-1',
      title: 'API outage',
      summary: 'Public API unavailable',
      severity: IncidentSeverity.sev1,
      now: t0,
    );

    expect(incident.status, IncidentStatus.declared);
    expect(
      () => incident.transitionTo(
        IncidentStatus.mitigated,
        t0.add(const Duration(minutes: 1)),
      ),
      throwsA(isA<IncidentDomainException>()),
    );
  });

  test('responder assignment is idempotent', () {
    final incident = Incident.create(
      id: 'inc-2',
      title: 'Queue delay',
      summary: '',
      severity: IncidentSeverity.sev2,
      now: t0,
    );
    final assigned = incident.assignResponder(
      'operator-17',
      t0.add(const Duration(minutes: 1)),
    );
    final replayed = assigned.assignResponder(
      'operator-17',
      t0.add(const Duration(minutes: 2)),
    );

    expect(assigned.responders, <String>['operator-17']);
    expect(replayed.revision, assigned.revision);
    expect(replayed.timeline.length, assigned.timeline.length);
  });

  test('alert acknowledgement is replay-safe', () {
    final incident = Incident.create(
      id: 'inc-3',
      title: 'Database saturation',
      summary: '',
      severity: IncidentSeverity.sev1,
      now: t0,
    );
    final raised = incident.raiseAlert(
      alertId: 'alert-1',
      message: 'Primary responder required',
      at: t0.add(const Duration(minutes: 1)),
    );
    final acknowledged = raised.acknowledgeAlert(
      'alert-1',
      t0.add(const Duration(minutes: 2)),
    );
    final replayed = acknowledged.acknowledgeAlert(
      'alert-1',
      t0.add(const Duration(minutes: 3)),
    );

    expect(acknowledged.alerts.single.isAcknowledged, isTrue);
    expect(replayed.revision, acknowledged.revision);
  });

  test('incident JSON round-trip preserves aggregate state', () {
    final original =
        Incident.create(
              id: 'inc-4',
              title: 'Storage pressure',
              summary: 'Volume above threshold',
              severity: IncidentSeverity.sev3,
              now: t0,
            )
            .assignResponder('responder-a', t0.add(const Duration(minutes: 1)))
            .addNote('Cleanup started', t0.add(const Duration(minutes: 2)));

    final restored = Incident.fromJson(original.toJson());

    expect(restored.id, original.id);
    expect(restored.revision, original.revision);
    expect(restored.responders, original.responders);
    expect(restored.timeline.length, original.timeline.length);
  });
}
