import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:incidentdeck/src/app/incident_deck_app.dart';
import 'package:incidentdeck/src/application/incident_service.dart';
import 'package:incidentdeck/src/data/incident_repository.dart';
import 'package:incidentdeck/src/domain/incident.dart';

void main() {
  IncidentService newService() {
    return IncidentService(repository: InMemoryIncidentRepository());
  }

  testWidgets('IncidentDeck renders the local incident workspace', (
    tester,
  ) async {
    await tester.pumpWidget(IncidentDeckApp(service: newService()));
    await tester.pumpAndSettle();

    expect(find.text('IncidentDeck'), findsOneWidget);
    expect(find.text('LOCAL DURABLE'), findsOneWidget);
    expect(find.text('Declare incident'), findsOneWidget);
    expect(find.text('No active incidents'), findsOneWidget);
  });

  testWidgets('resolved service survives app rebuilds', (tester) async {
    final service = newService();
    Future<IncidentService> factory() async => service;
    final app = IncidentDeckApp(serviceFactory: factory);

    await tester.pumpWidget(app);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Declare incident'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, 'Edge API degraded');
    await tester.enterText(find.byType(TextField).at(1), 'Elevated error rate');
    await tester.tap(find.text('Declare'));
    await tester.pumpAndSettle();

    expect(find.text('Edge API degraded'), findsOneWidget);
    expect(find.text('DECLARED'), findsOneWidget);

    await tester.pumpWidget(app);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Acknowledge'));
    await tester.pumpAndSettle();

    expect(find.text('ACKNOWLEDGED'), findsOneWidget);
  });

  testWidgets('incident detail supports responders notes and alerts', (
    tester,
  ) async {
    final service = IncidentService(
      repository: InMemoryIncidentRepository(),
      clock: () => DateTime.utc(2026, 9, 12, 14),
      idGenerator: (_) => 'inc-detail',
    );
    await service.declareIncident(
      title: 'Payments degraded',
      summary: 'Checkout latency is elevated',
      severity: IncidentSeverity.sev1,
    );

    await tester.pumpWidget(IncidentDeckApp(service: service));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Payments degraded'));
    await tester.pumpAndSettle();

    expect(find.text('Incident detail'), findsOneWidget);
    await tester.tap(find.text('Assign responder'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'on-call-a');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(find.text('on-call-a'), findsOneWidget);

    await tester.tap(find.text('Add note'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Investigating gateway');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(find.text('Investigating gateway'), findsOneWidget);

    await tester.tap(find.text('Raise alert'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Page incident commander');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(find.text('Page incident commander'), findsOneWidget);
    expect(find.textContaining('Awaiting acknowledgement'), findsOneWidget);
    expect(find.textContaining('Local delivery: unsupported'), findsOneWidget);

    await tester.tap(find.text('Acknowledge').last);
    await tester.pumpAndSettle();
    expect(find.textContaining('Acknowledged'), findsOneWidget);
  });

  testWidgets('workspace exposes semantic local controls', (tester) async {
    final semantics = tester.ensureSemantics();
    try {
      await tester.pumpWidget(IncidentDeckApp(service: newService()));
      await tester.pumpAndSettle();

      expect(
        find.bySemanticsLabel('Local notifications unsupported'),
        findsOneWidget,
      );
      expect(find.bySemanticsLabel('Import snapshot'), findsOneWidget);
      expect(find.bySemanticsLabel('Export snapshot'), findsOneWidget);
      expect(find.bySemanticsLabel('Declare incident'), findsWidgets);
    } finally {
      semantics.dispose();
    }
  });
}
