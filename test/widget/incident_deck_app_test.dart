import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:incidentdeck/src/app/incident_deck_app.dart';

void main() {
  testWidgets('IncidentDeck renders local incident workspace', (tester) async {
    await tester.pumpWidget(const IncidentDeckApp());
    await tester.pumpAndSettle();

    expect(find.text('IncidentDeck'), findsOneWidget);
    expect(find.text('LOCAL MODE'), findsOneWidget);
    expect(find.text('Declare incident'), findsOneWidget);
    expect(find.text('No active incidents'), findsOneWidget);
  });

  testWidgets('default local service survives app rebuilds', (tester) async {
    await tester.pumpWidget(const IncidentDeckApp());
    await tester.pumpAndSettle();

    await tester.tap(find.text('Declare incident'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, 'Edge API degraded');
    await tester.enterText(find.byType(TextField).at(1), 'Elevated error rate');
    await tester.tap(find.text('Declare'));
    await tester.pumpAndSettle();

    expect(find.text('Edge API degraded'), findsOneWidget);
    expect(find.text('DECLARED'), findsOneWidget);

    await tester.pumpWidget(const IncidentDeckApp());
    await tester.pumpAndSettle();
    await tester.tap(find.text('Acknowledge'));
    await tester.pumpAndSettle();

    expect(find.text('ACKNOWLEDGED'), findsOneWidget);
  });
}
