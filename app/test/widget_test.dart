import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:smartman/deck/deck.dart';
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

  Future<void> createDeckAndOpen(WidgetTester tester, String name) async {
    await tester.tap(find.byTooltip('New deck'));
    await tester.pumpAndSettle();
    await enterText(tester, 'Name', name);
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    await tester.tap(find.text(name));
    await tester.pumpAndSettle();
  }

  Future<void> addCard(WidgetTester tester, String front, String back) async {
    await tester.tap(find.byTooltip('New card'));
    await tester.pumpAndSettle();
    await enterText(tester, 'Front', front);
    await enterText(tester, 'Back', back);
    await tester.tap(find.byTooltip('Save card'));
    await tester.pumpAndSettle();
  }

  testWidgets('opens on an empty deck list', (tester) async {
    await pumpApp(tester);

    expect(find.text('Decks'), findsOneWidget);
    expect(find.text('No decks yet'), findsOneWidget);
    await unmountApp(tester);
  });

  testWidgets('shows Korean when the device locale is not supported', (
    tester,
  ) async {
    tester.platformDispatcher.localesTestValue = const [Locale('fr')];
    addTearDown(tester.platformDispatcher.clearLocalesTestValue);

    await pumpApp(tester);

    expect(find.text('덱'), findsOneWidget);
    expect(find.text('아직 덱이 없습니다'), findsOneWidget);
    await unmountApp(tester);
  });

  testWidgets(
    'a duplicate front offers open existing and add anyway, and add anyway stores it',
    (tester) async {
      await pumpApp(tester);
      await createDeckAndOpen(tester, 'French');

      await addCard(tester, 'Chat', 'cat');
      await addCard(tester, 'Chat', 'chat (talk)');

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

  testWidgets('a card with an empty side is not saved and says why', (
    tester,
  ) async {
    await pumpApp(tester);
    await createDeckAndOpen(tester, 'French');

    await addCard(tester, 'Chat', '');

    expect(find.text('Enter some text'), findsOneWidget);
    expect(find.text('Edit card'), findsNothing);
    expect(find.text('New card'), findsOneWidget);
    await unmountApp(tester);
  });

  testWidgets('a storage failure is shown to the user', (tester) async {
    await pumpApp(tester);
    await createDeckAndOpen(tester, 'French');
    final container = ProviderScope.containerOf(
      tester.element(find.byType(Scaffold).last),
    );
    final repository = container.read(deckRepositoryProvider);
    await tester.runAsync(() async {
      final deck = (await repository.watchDecks().first).single;
      await repository.deleteDeck(deck.id);
    });

    await addCard(tester, 'Chat', 'cat');

    expect(
      find.text(
        "Couldn't read or write the device's storage. Please try again.",
      ),
      findsOneWidget,
    );
    await unmountApp(tester);
  });

  testWidgets('tap targets on every screen carry labels', (tester) async {
    await pumpApp(tester);
    await createDeckAndOpen(tester, 'French');
    await addCard(tester, 'Chat', 'cat');

    await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
    await tester.tap(find.text('Chat'));
    await tester.pumpAndSettle();
    await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.pageBack();
    await tester.pumpAndSettle();
    await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
    await unmountApp(tester);
  });
}
