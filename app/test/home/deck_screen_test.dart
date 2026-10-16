import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:flutter/material.dart' hide Card;
import 'package:flutter_test/flutter_test.dart';
import 'package:smartman/deck/deck.dart';
import 'package:smartman/design/app_text_field.dart';
import 'package:smartman/home/src/deck_screen.dart';

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
        due: {'Chat'},
      );
      await screens.push((deck) => DeckScreen(deck: deck));

      expect(find.text('French'), findsOneWidget);
      expect(find.text('3 cards'), findsOneWidget);
      expect(find.text('1 to review'), findsOneWidget);
      expect(find.text('2 new'), findsOneWidget);

      await screens.tap(find.text('Study · 3'));

      expect(screens.session, {screens.deck.id});
      await screens.close();
    },
  );

  testWidgets(
    'in a backlog the header says new cards wait, and not otherwise',
    (tester) async {
      const paused = 'New cards wait until you catch up on your reviews.';
      // Three reviews due after 30-day intervals are far more than three
      // days' load.
      var screens = await DeckScreens.open(
        tester,
        cards: cards,
        due: cards.keys.toSet(),
        dueDays: 30,
      );
      await screens.push((deck) => DeckScreen(deck: deck));

      expect(find.text('3 to review'), findsOneWidget);
      expect(find.text('0 new'), findsOneWidget);
      expect(find.text(paused), findsOneWidget);
      await screens.close();

      // Control: the same reviews after one-day intervals are within three
      // days' load, so the header has no such sentence.
      screens = await DeckScreens.open(
        tester,
        cards: cards,
        due: cards.keys.toSet(),
      );
      await screens.push((deck) => DeckScreen(deck: deck));

      expect(find.text('3 to review'), findsOneWidget);
      expect(find.text('0 new'), findsOneWidget);
      expect(find.text(paused), findsNothing);
      await screens.close();
    },
  );

  testWidgets(
    'with nothing to study today, or no count yet or none readable, Study still opens a session over the deck',
    (tester) async {
      const unreadable =
          "Couldn't read or write the device's storage. Please try again.";
      for (final (today, open, counted, failed) in [
        (
          'nothing to study',
          () =>
              DeckScreens.open(tester, cards: cards, later: cards.keys.toSet()),
          true,
          false,
        ),
        (
          'no count yet',
          () => DeckScreens.open(tester, stalled: true),
          false,
          false,
        ),
        (
          'no count readable',
          () => DeckScreens.open(tester, cards: cards, unreadable: true),
          false,
          true,
        ),
      ]) {
        final screens = await open();
        await screens.push((deck) => DeckScreen(deck: deck));
        // The count is in the state the case names: read as zero, pending,
        // or failed.
        expect(
          find.text('0 to review'),
          counted ? findsOneWidget : findsNothing,
          reason: today,
        );
        expect(
          find.text(unreadable),
          failed ? findsOneWidget : findsNothing,
          reason: today,
        );

        await screens.tap(find.text('Study · 0'));

        expect(screens.session, {screens.deck.id}, reason: today);
        await screens.close();
      }
    },
  );

  testWidgets('cards show as front | back rows, and a tap opens one to edit', (
    tester,
  ) async {
    final screens = await DeckScreens.open(tester, cards: cards);
    await screens.push((deck) => DeckScreen(deck: deck));
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
      await screens.push((deck) => DeckScreen(deck: deck));

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
    await screens.push((deck) => DeckScreen(deck: deck));

    expect(find.text('Add card'), findsOneWidget);
    expect(find.text('Add from photo'), findsNothing);
    await screens.close();
  });

  testWidgets('with photo import, the photo button opens it for this deck', (
    tester,
  ) async {
    final screens = await DeckScreens.open(tester, photoImport: true);
    await screens.push((deck) => DeckScreen(deck: deck));

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
      await screens.push((deck) => DeckScreen(deck: deck));

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
      expect(find.byType(DeckScreen), findsNothing);
      await screens.close();
    },
  );

  testWidgets('the deck menu renames the deck', (tester) async {
    final screens = await DeckScreens.open(tester);
    await screens.push((deck) => DeckScreen(deck: deck));

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
      await screens.push((deck) => DeckScreen(deck: deck));
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
      await screens.push((deck) => DeckScreen(deck: deck));

      await screens.tap(find.byTooltip('Deck actions'));
      await screens.tap(find.text('Delete deck'));
      expect(find.text('Its 3 cards will be deleted too.'), findsOneWidget);
      await screens.tap(find.text('Delete'));

      expect(find.byType(DeckScreen), findsNothing);
      final decks = await tester.runAsync(
        () => screens.repository.watchDecks().first,
      );
      expect(decks, isEmpty);
      await screens.close();
    },
  );
}
