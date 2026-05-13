import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kersylva_ops/main.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('opens the operations sections from bottom navigation', (
    tester,
  ) async {
    await tester.pumpWidget(const KersylvaOpsApp());
    await tester.pumpAndSettle();

    expect(
      find.text('Daily coordination for people, costs, quality, and bookings.'),
      findsOneWidget,
    );

    await tester.tap(find.text('Team'));
    await tester.pumpAndSettle();
    expect(find.text('Employee directory (4)'), findsOneWidget);
    expect(find.text('Claire Martin'), findsOneWidget);

    await tester.tap(find.text('Quality'));
    await tester.pumpAndSettle();
    expect(find.text('Quality control checklist'), findsOneWidget);
    expect(find.text('Verify safety signage at north access'), findsOneWidget);
  });

  testWidgets('saves a local expense record', (tester) async {
    await tester.pumpWidget(const KersylvaOpsApp());
    await tester.pumpAndSettle();

    await tester.tap(find.text('Spend'));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.add_card_outlined));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextFormField).at(0), 'Office supplies');
    await tester.enterText(find.byType(TextFormField).at(1), '42.50');
    await tester.enterText(
      find.byType(TextFormField).at(2),
      'Notebooks for review desk',
    );
    await tester.tap(find.text('Save expense'));
    await tester.pumpAndSettle();

    expect(find.text('Office supplies'), findsOneWidget);
    expect(find.text('42.50 EUR'), findsOneWidget);
  });

  testWidgets('settings shows the local privacy statement', (tester) async {
    await tester.pumpWidget(const KersylvaOpsApp());
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.settings_outlined));
    await tester.pumpAndSettle();

    expect(find.text('Settings & privacy'), findsOneWidget);
    expect(find.text('No account or cloud sync'), findsOneWidget);
    expect(
      find.textContaining('stores expenses, quality checks'),
      findsOneWidget,
    );
  });
}
