import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:smartman/main.dart';

void main() {
  Future<void> pumpApp(WidgetTester tester) async {
    await tester.pumpWidget(composeApp(NativeDatabase.memory()));
    await tester.pumpAndSettle();
  }

  // Unmounting the scope cancels drift's stream queries, whose cleanup timer
  // must fire before the test body ends.
  Future<void> unmountApp(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 1));
  }

  Future<void> enterText(WidgetTester tester, String label, String text) =>
      tester.enterText(find.widgetWithText(TextField, label), text);

  testWidgets('opens on an empty deck list', (tester) async {
    await pumpApp(tester);

    expect(find.text('Decks'), findsOneWidget);
    expect(find.text('No decks yet'), findsOneWidget);
    await unmountApp(tester);
  });

  testWidgets(
    'a duplicate front offers open existing and add anyway, and add anyway stores it',
    (tester) async {
      await pumpApp(tester);

      await tester.tap(find.byTooltip('New deck'));
      await tester.pumpAndSettle();
      await enterText(tester, 'Name', 'French');
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('French'));
      await tester.pumpAndSettle();

      for (final back in ['cat', 'chat (talk)']) {
        await tester.tap(find.byTooltip('New card'));
        await tester.pumpAndSettle();
        await enterText(tester, 'Front', 'Chat');
        await enterText(tester, 'Back', back);
        await tester.tap(find.byTooltip('Save card'));
        await tester.pumpAndSettle();
      }

      expect(find.text('Duplicate front'), findsOneWidget);
      expect(find.text('Open existing card'), findsOneWidget);
      expect(find.text('cat'), findsNothing);

      await tester.tap(find.text('Add anyway'));
      await tester.pumpAndSettle();

      expect(find.text('cat'), findsOneWidget);
      expect(find.text('chat (talk)'), findsOneWidget);
      await unmountApp(tester);
    },
  );
}
