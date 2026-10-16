import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:flutter/material.dart' hide Card;
import 'package:flutter_test/flutter_test.dart';
import 'package:smartman/deck/deck.dart';
import 'package:smartman/deck/src/card_list_screen.dart';
import 'package:smartman/design/app_text_field.dart';

import 'deck_screens.dart';

/// The front of every card row on screen, top to bottom.
List<String?> _rowFronts(WidgetTester tester) => [
  for (final row
      in find
          .ancestor(
            of: find.byType(VerticalDivider),
            matching: find.byType(Row),
          )
          .evaluate())
    tester
        .widget<Text>(
          find
              .descendant(
                of: find.byElementPredicate((element) => element == row),
                matching: find.byType(Text),
              )
              .first,
        )
        .data,
];

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  const cards = {'Chat': 'cat', 'Chien': 'dog', 'Hund': 'DOG'};

  testWidgets(
    "the header names the deck, counts its cards and today's, and Study opens a session over it",
    (tester) async {
      final screens = await DeckScreens.open(
        tester,
        cards: cards,
        today: const TodayCounted(review: 1, fresh: 2),
      );
      await screens.push((deck) => CardListScreen(deck: deck));

      expect(find.text('French'), findsOneWidget);
      expect(find.text('3 cards'), findsOneWidget);
      expect(find.text('1 to review'), findsOneWidget);
      expect(find.text('2 new'), findsOneWidget);

      await screens.tap(find.text('Study · 3'));

      expect(screens.sessions, [
        {screens.deck.id},
      ]);
      await screens.close();
    },
  );

  testWidgets(
    'in a backlog the header says new cards wait, and not otherwise',
    (tester) async {
      const paused = 'New cards wait until you catch up on your reviews.';
      var screens = await DeckScreens.open(
        tester,
        cards: cards,
        today: const TodayCounted.backlog(review: 3),
      );
      await screens.push((deck) => CardListScreen(deck: deck));

      expect(find.text('3 to review'), findsOneWidget);
      expect(find.text('0 new'), findsOneWidget);
      expect(find.text(paused), findsOneWidget);
      await screens.close();

      // Control: the same count with new cards taken has no such sentence.
      screens = await DeckScreens.open(
        tester,
        cards: cards,
        today: const TodayCounted(review: 3, fresh: 0),
      );
      await screens.push((deck) => CardListScreen(deck: deck));

      expect(find.text('3 to review'), findsOneWidget);
      expect(find.text('0 new'), findsOneWidget);
      expect(find.text(paused), findsNothing);
      await screens.close();
    },
  );

  testWidgets(
    'with nothing to study today, or no count yet or none readable, Study still opens a session over the deck',
    (tester) async {
      for (final today in const [
        TodayCounted(review: 0, fresh: 0),
        TodayPending(),
        TodayUnavailable('Could not count'),
      ]) {
        final screens = await DeckScreens.open(
          tester,
          cards: cards,
          today: today,
        );
        await screens.push((deck) => CardListScreen(deck: deck));

        await screens.tap(find.text('Study · 0'));

        expect(screens.sessions, [
          {screens.deck.id},
        ], reason: '$today');
        expect(find.text('session'), findsOneWidget);
        await screens.close();
      }
    },
  );

  testWidgets('cards show as front | back rows, and a tap opens one to edit', (
    tester,
  ) async {
    final screens = await DeckScreens.open(tester, cards: cards);
    await screens.push((deck) => CardListScreen(deck: deck));
    expect(_rowFronts(tester), ['Chat', 'Chien', 'Hund']);

    await screens.tap(find.text('Chien'));

    expect(find.text('Edit card'), findsOneWidget);
    expect(find.widgetWithText(TextField, 'Chien'), findsOneWidget);
    await screens.close();
  });

  testWidgets(
    'search keeps the cards whose front or back holds the text, ignoring case',
    (tester) async {
      final screens = await DeckScreens.open(tester, cards: cards);
      await screens.push((deck) => CardListScreen(deck: deck));

      await screens.enter('Search', 'dog');
      expect(_rowFronts(tester), ['Chien', 'Hund']);

      await screens.enter('Search', 'CHAT');
      expect(_rowFronts(tester), ['Chat']);

      await screens.enter('Search', 'zebra');
      expect(_rowFronts(tester), isEmpty);
      expect(find.text('No card matches. Try other words.'), findsOneWidget);

      await screens.enter('Search', '');
      expect(_rowFronts(tester), ['Chat', 'Chien', 'Hund']);
      await screens.close();
    },
  );

  testWidgets('the photo button is absent until photo import exists', (
    tester,
  ) async {
    final screens = await DeckScreens.open(tester);
    await screens.push((deck) => CardListScreen(deck: deck));

    expect(find.text('Add card'), findsOneWidget);
    expect(find.text('Add from photo'), findsNothing);
    await screens.close();
  });

  testWidgets('with photo import, the photo button opens it for this deck', (
    tester,
  ) async {
    final screens = await DeckScreens.open(tester, photoImport: true);
    await screens.push((deck) => CardListScreen(deck: deck));

    await screens.tap(find.text('Add from photo'));

    expect(find.text('photo import'), findsOneWidget);
    expect(screens.photoImports, [screens.deck.id]);
    await screens.close();
  });

  testWidgets(
    'a photo import into another deck replaces this list with that deck, and one into this deck returns here',
    (tester) async {
      final screens = await DeckScreens.open(tester, photoImport: true);
      final other = (await tester.runAsync(
        () => screens.repository.createDeck('Spanish'),
      ))!;
      await screens.push((deck) => CardListScreen(deck: deck));

      Future<void> saveInto(Deck deck) async {
        await screens.tap(find.text('Add from photo'));
        screens.navigator.currentState!.pop(deck);
        await tester.pumpAndSettle();
      }

      await saveInto(screens.deck);
      expect(find.text('French'), findsOneWidget);

      await saveInto(other);
      expect(find.text('Spanish'), findsOneWidget);
      expect(find.text('French'), findsNothing);
      screens.navigator.currentState!.pop();
      await tester.pumpAndSettle();
      expect(find.byType(CardListScreen), findsNothing);
      await screens.close();
    },
  );

  testWidgets('the deck menu renames the deck', (tester) async {
    final screens = await DeckScreens.open(tester);
    await screens.push((deck) => CardListScreen(deck: deck));

    await screens.tap(find.byTooltip('Deck actions'));
    await screens.tap(find.text('Rename'));
    await screens.enter('Deck name', 'Français');
    await screens.tap(find.text('Save'));

    expect(find.text('Français'), findsOneWidget);
    final decks = await tester.runAsync(
      () => screens.repository.watchDecks().first,
    );
    expect(decks!.single.name, 'Français');
    await screens.close();
  });

  testWidgets(
    'the rename sheet opens focused on the current name, refuses an empty one, and saves on Enter',
    (tester) async {
      final screens = await DeckScreens.open(tester);
      await screens.push((deck) => CardListScreen(deck: deck));
      await screens.tap(find.byTooltip('Deck actions'));
      await screens.tap(find.text('Rename'));
      EditableText field() => tester.widget<EditableText>(
        find.descendant(
          of: find.widgetWithText(AppTextField, 'Deck name'),
          matching: find.byType(EditableText),
        ),
      );
      expect(field().focusNode.hasFocus, isTrue);
      expect(field().controller.text, 'French');

      await screens.enter('Deck name', '  ');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      expect(find.text('Enter a name'), findsOneWidget);
      expect(find.byType(BottomSheet), findsOneWidget);

      await screens.enter('Deck name', 'Français');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      expect(find.byType(BottomSheet), findsNothing);
      final decks = await tester.runAsync(
        () => screens.repository.watchDecks().first,
      );
      expect(decks!.single.name, 'Français');
      await screens.close();
    },
  );

  testWidgets(
    'the deck menu deletes the deck after confirming, and closes it',
    (tester) async {
      final screens = await DeckScreens.open(tester, cards: cards);
      await screens.push((deck) => CardListScreen(deck: deck));

      await screens.tap(find.byTooltip('Deck actions'));
      await screens.tap(find.text('Delete deck'));
      expect(find.text('Its 3 cards will be deleted too.'), findsOneWidget);
      await screens.tap(find.text('Delete'));

      expect(find.byType(CardListScreen), findsNothing);
      final decks = await tester.runAsync(
        () => screens.repository.watchDecks().first,
      );
      expect(decks, isEmpty);
      await screens.close();
    },
  );
}
