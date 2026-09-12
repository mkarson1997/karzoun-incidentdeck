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
}
