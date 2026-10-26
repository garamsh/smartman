import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:flutter/material.dart' hide Card;
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:smartman/deck/deck.dart';
import 'package:smartman/design/app_button.dart';
import 'package:smartman/design/app_text_field.dart';
import 'package:smartman/design/theme.dart';
import 'package:smartman/home/src/deck_screen.dart';
import 'package:smartman/home/src/progress_bar.dart';
import 'package:smartman/photo_import/photo_import.dart';
import 'package:smartman/study/study.dart' show StudyScreen;

import '../deck/whole_cards.dart';
import '../study/minutes_sheet.dart';
import 'contrast.dart';
import 'deck_screens.dart';

/// The front of every card row on screen, top to bottom.
List<String> _rowFronts(WidgetTester tester) => [
  for (final row in tester.widgetList<CardBackRow>(find.byType(CardBackRow)))
    plainText(row.front),
];

/// The deck page's "뜻 보기" switch.
Switch _switch(WidgetTester tester) =>
    tester.widget<Switch>(find.byType(Switch));

/// The back of every card row on screen that shows it, top to bottom.
List<String> _answers(WidgetTester tester) => [
  for (final row in tester.widgetList<CardBackRow>(find.byType(CardBackRow)))
    if (row.shown) plainText(row.back),
];

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  const cards = {'Chat': 'cat', 'Chien': 'dog', 'Hund': 'DOG'};

  testWidgets(
    'a deck with no card offers adding one as its one primary action, and no Study',
    (tester) async {
      AppButton button(String label) =>
          tester.widget<AppButton>(find.widgetWithText(AppButton, label));
      // Control: a deck with a card offers Study, and adding a card is quieter.
      var screens = await DeckScreens.open(tester, cards: {'Chat': 'cat'});
      await screens.push((deck) => DeckScreen(deck: deck));
      expect(find.widgetWithText(AppButton, 'Study'), findsOneWidget);
      expect(button('Add card').variant, AppButtonVariant.secondary);
      await screens.close();

      screens = await DeckScreens.open(tester);
      await screens.push((deck) => DeckScreen(deck: deck));
      expect(find.text('No cards yet. Add a card to start.'), findsOneWidget);
      expect(find.widgetWithText(AppButton, 'Study'), findsNothing);
      expect(button('Add card').variant, AppButtonVariant.primary);
      await screens.close();
    },
  );

  testWidgets(
    'a deck with no card shows no today card of zeros, where a deck with one shows its count, mastered line and bar',
    (tester) async {
      // Control: a deck with a card has its today card.
      var screens = await DeckScreens.open(tester, cards: {'Chat': 'cat'});
      await screens.push((deck) => DeckScreen(deck: deck));
      expect(find.text("Today's cards"), findsOneWidget);
      expect(find.text('0 of 1 mastered'), findsOneWidget);
      expect(find.byType(ProgressBar), findsOneWidget);
      await screens.close();

      screens = await DeckScreens.open(tester);
      await screens.push((deck) => DeckScreen(deck: deck));
      expect(find.text('No cards yet. Add a card to start.'), findsOneWidget);
      expect(find.text("Today's cards"), findsNothing);
      expect(find.textContaining('mastered'), findsNothing);
      expect(find.byType(ProgressBar), findsNothing);
      await screens.close();
    },
  );

  for (final mode in [ThemeMode.light, ThemeMode.dark]) {
    testWidgets(
      'in the ${mode.name} theme the deck\'s today card is white with an ink Study button, and meets the contrast guideline',
      (tester) async {
        final screens = await DeckScreens.open(
          tester,
          cards: cards,
          due: {'Chat'},
          themeMode: mode,
        );
        await screens.push((deck) => DeckScreen(deck: deck));
        final colors = AppColors.of(tester.element(find.byType(DeckScreen)));
        final study = find.widgetWithText(AppButton, 'Study');
        final card = find
            .ancestor(
              of: study,
              matching: find.byWidgetPredicate(
                (widget) =>
                    widget is DecoratedBox &&
                    widget.decoration is BoxDecoration &&
                    (widget.decoration as BoxDecoration).borderRadius ==
                        BorderRadius.circular(AppRadius.card),
              ),
            )
            .first;
        expect(
          (tester.widget<DecoratedBox>(card).decoration as BoxDecoration).color,
          colors.surface,
        );
        expect(
          tester.widget<AppButton>(study).variant,
          AppButtonVariant.primary,
        );
        expect(
          find.descendant(of: card, matching: find.byType(ProgressBar)),
          findsOneWidget,
        );
        expectTextReadable(tester, card, colors.surface);
        await expectLater(tester, meetsGuideline(textContrastGuideline));
        await screens.close();
      },
    );
  }

  testWidgets(
    "Customize deck in the menu names each icon and colour as a 48 pt button, previews the choice, and Save stores it on the header's tile",
    (tester) async {
      final screens = await DeckScreens.open(tester, cards: cards);
      await screens.push((deck) => DeckScreen(deck: deck));
      Finder header(IconData icon) => find.descendant(
        of: find.byType(DeckTile),
        matching: find.byIcon(icon),
      );
      expect(header(LucideIcons.layers), findsOneWidget);

      await screens.tap(find.byTooltip('Deck actions'));
      await screens.tap(find.text('Customize deck'));
      // The deck's own default pair is selected, and every option is a
      // labelled button with a selected state, at least 48 square.
      expect(
        tester.getSemantics(find.bySemanticsLabel('Cards')),
        isSemantics(isButton: true, hasSelectedState: true, isSelected: true),
      );
      expect(
        tester.getSemantics(find.bySemanticsLabel('Book')),
        isSemantics(isButton: true, hasSelectedState: true, isSelected: false),
      );
      for (final option in ['Cards', 'Star', 'Blue', 'Slate']) {
        final size = tester.getSize(find.bySemanticsLabel(option));
        expect(size.width, greaterThanOrEqualTo(48), reason: option);
        expect(size.height, greaterThanOrEqualTo(48), reason: option);
      }

      await screens.tap(find.bySemanticsLabel('Book'));
      await screens.tap(find.bySemanticsLabel('Amber'));
      // The sheet's preview shows the pair before it is saved.
      expect(header(LucideIcons.bookOpen), findsOneWidget);
      expect(
        tester.getSemantics(find.bySemanticsLabel('Book')),
        isSemantics(isButton: true, hasSelectedState: true, isSelected: true),
      );
      await screens.tap(find.text('Save'));

      expect(find.text('Customize deck'), findsNothing);
      expect(header(LucideIcons.bookOpen), findsOneWidget);
      expect(header(LucideIcons.layers), findsNothing);
      final stored = (await tester.runAsync(
        () => screens.repository.getDeck(screens.deck.id),
      ))!;
      expect((stored.icon, stored.color), (DeckIcon.book, DeckColor.amber));
      await screens.close();
    },
  );

  testWidgets('dismissing Customize deck keeps the deck as it was', (
    tester,
  ) async {
    final screens = await DeckScreens.open(tester, cards: cards);
    await screens.push((deck) => DeckScreen(deck: deck));

    await screens.tap(find.byTooltip('Deck actions'));
    await screens.tap(find.text('Customize deck'));
    await screens.tap(find.bySemanticsLabel('Book'));
    Finder onTile(IconData icon) =>
        find.descendant(of: find.byType(DeckTile), matching: find.byIcon(icon));
    // Control: the choice was made, so the sheet's preview shows it.
    expect(onTile(LucideIcons.bookOpen), findsOneWidget);
    await tester.tapAt(const Offset(195, 40));
    await tester.pumpAndSettle();

    expect(onTile(LucideIcons.bookOpen), findsNothing);
    expect(onTile(LucideIcons.layers), findsOneWidget);
    final stored = (await tester.runAsync(
      () => screens.repository.getDeck(screens.deck.id),
    ))!;
    expect((stored.icon, stored.color), (null, null));
    await screens.close();
  });

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
      expect(find.bySemanticsLabel('3 cards for today'), findsOneWidget);
      // Chat was reviewed after a day's interval, so it is learning.
      expect(find.text('0 of 3 mastered'), findsOneWidget);
      expect(
        find.bySemanticsLabel('0 mastered, 1 learning, 2 new'),
        findsOneWidget,
      );
      // The learning count is the bar's label alone, with no line of it.
      expect(find.textContaining('learning'), findsNothing);

      await screens.tap(find.text('Study'));

      expect(screens.session, {screens.deck.id});
      await screens.close();
    },
  );

  testWidgets(
    'a first session asks for the daily study minutes once, before it opens',
    (tester) async {
      final screens = await DeckScreens.open(
        tester,
        cards: cards,
        minutesAsked: false,
      );
      await screens.push((deck) => DeckScreen(deck: deck));

      await screens.tap(find.text('Study'));
      expect(
        find.byWidgetPredicate(
          (widget) =>
              widget is Text &&
              widget.data?.replaceAll('\u2060', '') ==
                  'How many minutes a day will you study?',
        ),
        findsOneWidget,
      );
      expect(find.byType(StudyScreen), findsNothing);
      await waitForPicker(tester);
      await screens.tap(find.byTooltip('5 minutes less'));
      await screens.tap(find.text('Save'));

      expect(screens.session, {screens.deck.id});
      // Control: once shown, the next session opens at once.
      screens.navigator.currentState?.pop();
      await tester.pumpAndSettle();
      await screens.tap(find.text('Study'));
      expect(find.byType(BottomSheet), findsNothing);
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

      expect(find.bySemanticsLabel('3 cards for today'), findsOneWidget);
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

      expect(find.bySemanticsLabel('3 cards for today'), findsOneWidget);
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
          () => DeckScreens.open(tester, cards: cards, stalled: true),
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
          find.bySemanticsLabel('0 cards for today'),
          counted ? findsOneWidget : findsNothing,
          reason: today,
        );
        expect(
          find.text(unreadable),
          failed ? findsOneWidget : findsNothing,
          reason: today,
        );

        await screens.tap(find.text('Study'));

        expect(screens.session, {screens.deck.id}, reason: today);
        await screens.close();
      }
    },
  );

  testWidgets(
    'each card shows its front with the back hidden, a tap shows it and a second hides it',
    (tester) async {
      final screens = await DeckScreens.open(tester, cards: cards);
      await screens.push((deck) => DeckScreen(deck: deck));
      expect(_rowFronts(tester), ['Chat', 'Chien', 'Hund']);
      expect(find.text('dog'), findsNothing);
      expect(find.bySemanticsLabel('Chien, back hidden'), findsOneWidget);

      await screens.tap(find.text('Chien'));
      expect(find.text('dog'), findsOneWidget);
      expect(find.bySemanticsLabel('Chien, back dog'), findsOneWidget);
      // Control: the other cards keep their answers hidden.
      expect(find.text('cat'), findsNothing);

      await screens.tap(find.text('Chien'));
      expect(find.text('dog'), findsNothing);
      expect(find.byType(CardEditorScreen), findsNothing);
      await screens.close();
    },
  );

  testWidgets(
    'a cloze card shows its front with its blank empty in place of the bar over the back, and a tap fills it in place',
    (tester) async {
      const cloze = ClozeContent('The capital of France is ___', ['Paris']);
      final screens = await DeckScreens.open(tester, cards: {'Chat': 'cat'});
      await tester.runAsync(
        () => screens.repository.addCard(
          screens.deck.id,
          front: [cloze],
          back: [const TextContent('The capital of France is Paris')],
        ),
      );
      await screens.push((deck) => DeckScreen(deck: deck));
      final row = find.byWidgetPredicate(
        (widget) => widget is CardBackRow && widget.front.first == cloze,
      );
      expect(row, findsOneWidget);
      expect(
        find.bySemanticsLabel('The capital of France is blank, back hidden'),
        findsOneWidget,
      );
      expect(blanksUnder(row), {'Paris': false});
      expect(find.text('The capital of France is Paris'), findsNothing);

      await screens.tap(row);
      expect(blanksUnder(row), {'Paris': true});
      expect(
        find.bySemanticsLabel(
          'The capital of France is blank, back The capital of France is Paris',
        ),
        findsOneWidget,
      );
      // Control: the split card keeps its back hidden.
      expect(find.text('cat'), findsNothing);
      await screens.close();
    },
  );

  testWidgets(
    'the Show meanings switch is off on opening, on shows every back and off hides them',
    (tester) async {
      final screens = await DeckScreens.open(tester, cards: cards);
      await screens.push((deck) => DeckScreen(deck: deck));
      expect(find.text('Cards 3'), findsOneWidget);
      expect(_switch(tester).value, isFalse);
      expect(_answers(tester), isEmpty);

      await screens.tap(find.byType(Switch));
      expect(_switch(tester).value, isTrue);
      expect(_answers(tester), ['cat', 'dog', 'DOG']);

      await screens.tap(find.byType(Switch));
      expect(_switch(tester).value, isFalse);
      expect(_answers(tester), isEmpty);
      await screens.close();
    },
  );

  testWidgets(
    'a tap after the switch flips only that card, and the switch then sets every card to its state',
    (tester) async {
      final screens = await DeckScreens.open(tester, cards: cards);
      await screens.push((deck) => DeckScreen(deck: deck));

      await screens.tap(find.byType(Switch));
      await screens.tap(find.text('Chien'));
      expect(_answers(tester), ['cat', 'DOG']);

      // Off hides every answer, the one the tap hid included.
      await screens.tap(find.byType(Switch));
      expect(_answers(tester), isEmpty);
      await screens.tap(find.text('Hund'));
      expect(_answers(tester), ['DOG']);

      // On shows every answer, the one the tap showed included.
      await screens.tap(find.byType(Switch));
      expect(_answers(tester), ['cat', 'dog', 'DOG']);
      await screens.close();
    },
  );

  testWidgets('search results follow the switch', (tester) async {
    final screens = await DeckScreens.open(tester, cards: cards);
    await screens.push((deck) => DeckScreen(deck: deck));
    await screens.tap(find.byType(Switch));

    await screens.tap(find.byTooltip('Search cards'));
    await screens.enter('Search', 'ch');
    expect(_rowFronts(tester), ['Chat', 'Chien']);
    expect(find.text('Cards 2'), findsOneWidget);
    expect(_answers(tester), ['cat', 'dog']);

    await screens.tap(find.byType(Switch));
    expect(_answers(tester), isEmpty);
    await screens.close();
  });

  testWidgets(
    'the switch is read as Show meanings with its state, and stays pinned while the list scrolls',
    (tester) async {
      final semantics = tester.ensureSemantics();
      final screens = await DeckScreens.open(
        tester,
        cards: {for (var i = 0; i < 30; i++) 'word $i': 'answer $i'},
      );
      await screens.push((deck) => DeckScreen(deck: deck));

      expect(
        tester.getSemantics(find.byType(Switch)),
        isSemantics(
          label: 'Show meanings',
          hasToggledState: true,
          isToggled: false,
        ),
      );
      await screens.tap(find.byType(Switch));
      expect(
        tester.getSemantics(find.byType(Switch)),
        isSemantics(
          label: 'Show meanings',
          hasToggledState: true,
          isToggled: true,
        ),
      );

      final top = tester.getTopLeft(find.text('Cards 30')).dy;
      expect(find.text('word 0'), findsOneWidget);
      await tester.drag(find.byType(CustomScrollView), const Offset(0, -600));
      await tester.pumpAndSettle();
      // The list scrolled past its first card and the today card.
      expect(find.text('word 0'), findsNothing);
      expect(find.text('Study'), findsNothing);
      expect(tester.getTopLeft(find.text('Cards 30')).dy, lessThan(top));
      expect(
        tester.getTopLeft(find.text('Cards 30')).dy,
        greaterThanOrEqualTo(tester.getBottomLeft(find.byType(AppBar)).dy),
      );
      await screens.tap(find.byType(Switch));
      expect(_switch(tester).value, isFalse);
      semantics.dispose();
      await screens.close();
    },
  );

  testWidgets(
    'a long-press, or a screen reader\'s action, opens a card to edit',
    (tester) async {
      final screens = await DeckScreens.open(tester, cards: cards);
      await screens.push((deck) => DeckScreen(deck: deck));

      await tester.longPress(find.text('Chien'));
      await tester.pumpAndSettle();
      expect(find.text('Edit card'), findsOneWidget);
      expect(find.widgetWithText(TextField, 'Chien'), findsOneWidget);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();

      final semantics = tester.ensureSemantics();
      // The row's toggle, the node beside its pencil.
      final node = tester.getSemantics(
        find
            .descendant(
              of: find.byType(CardBackRow).first,
              matching: find.byType(InkWell),
            )
            .first,
      );
      final edit = CustomSemanticsAction.getIdentifier(
        const CustomSemanticsAction(label: 'Edit card'),
      );
      expect(node.getSemanticsData().customSemanticsActionIds, contains(edit));
      tester
          .renderObject(find.byType(CardBackRow).first)
          .owner!
          .semanticsOwner!
          .performAction(node.id, SemanticsAction.customAction, edit);
      await tester.pumpAndSettle();
      expect(find.widgetWithText(TextField, 'Chat'), findsOneWidget);
      semantics.dispose();
      await screens.close();
    },
  );

  testWidgets(
    "each card row's pencil, a button a screen reader hears as Edit card, opens that card, while a tap on the row still shows its back",
    (tester) async {
      final semantics = tester.ensureSemantics();
      final screens = await DeckScreens.open(tester, cards: cards);
      await screens.push((deck) => DeckScreen(deck: deck));
      final pencils = find.byTooltip('Edit card');
      expect(pencils, findsNWidgets(3), reason: 'one on each row');
      expect(
        tester.getSemantics(pencils.at(1)),
        isSemantics(tooltip: 'Edit card', isButton: true, hasTapAction: true),
      );

      // Control: a tap on the row shows its back and opens nothing.
      await screens.tap(find.text('Chien'));
      expect(_answers(tester), ['dog']);
      expect(find.byType(TextField), findsNothing);

      await screens.tap(pencils.at(1));
      expect(find.widgetWithText(TextField, 'Chien'), findsOneWidget);
      semantics.dispose();
      await screens.close();
    },
  );

  testWidgets(
    'search keeps the cards whose front or back holds the text, ignoring case',
    (tester) async {
      final screens = await DeckScreens.open(tester, cards: cards);
      await screens.push((deck) => DeckScreen(deck: deck));
      expect(find.byType(AppTextField), findsNothing);

      await screens.tap(find.byTooltip('Search cards'));
      await screens.enter('Search', 'dog');
      expect(_rowFronts(tester), ['Chien', 'Hund']);

      await screens.enter('Search', 'CHAT');
      expect(_rowFronts(tester), ['Chat']);

      await screens.enter('Search', 'zebra');
      expect(_rowFronts(tester), isEmpty);
      expect(find.text('No card matches. Try other words.'), findsOneWidget);

      await screens.enter('Search', 'CHAT');
      await screens.tap(find.byTooltip('Close search'));
      expect(find.byType(AppTextField), findsNothing);
      expect(_rowFronts(tester), ['Chat', 'Chien', 'Hund']);
      await screens.close();
    },
  );

  testWidgets(
    'while searching above a phone keyboard, the first match starts under the top bar and shows above the keyboard',
    (tester) async {
      final screens = await DeckScreens.open(tester, cards: cards);
      await screens.push((deck) => DeckScreen(deck: deck));
      // Control: before the search, the deck's header and today card are up.
      expect(find.byType(DeckTile), findsOneWidget);
      expect(find.text("Today's cards"), findsOneWidget);

      await screens.tap(find.byTooltip('Search cards'));
      tester.view.viewInsets = const FakeViewPadding(bottom: 336);
      addTearDown(tester.view.resetViewInsets);
      await screens.enter('Search', 'ch');
      await tester.pumpAndSettle();
      expect(tester.view.viewInsets.bottom, 336, reason: 'the keyboard is up');

      final first = tester.getRect(find.byType(CardBackRow).first);
      final topBar = tester.getRect(find.byType(AppBar));
      expect(first.bottom, lessThanOrEqualTo(844 - 336));
      expect(first.top - topBar.bottom, lessThan(AppSize.tapTarget * 2));
      expect(find.byType(DeckTile), findsNothing);
      expect(find.text("Today's cards"), findsNothing);
      await screens.close();
    },
  );

  testWidgets(
    'the back closes an open search and keeps the screen, and a second back leaves it',
    (tester) async {
      final screens = await DeckScreens.open(tester, cards: cards);
      await screens.push((deck) => DeckScreen(deck: deck));
      await screens.tap(find.byTooltip('Search cards'));
      await screens.enter('Search', 'ch');

      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.byType(AppTextField), findsNothing);
      expect(find.byType(DeckScreen), findsOneWidget);
      expect(_rowFronts(tester), ['Chat', 'Chien', 'Hund']);

      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.byType(DeckScreen), findsNothing);
      await screens.close();
    },
  );

  testWidgets(
    '"Delete deck" is drawn in the destructive text colour, where "Rename" is not',
    (tester) async {
      final screens = await DeckScreens.open(tester);
      await screens.push((deck) => DeckScreen(deck: deck));
      await screens.tap(find.byTooltip('Deck actions'));

      final colors = AppColors.of(tester.element(find.text('Delete deck')));
      expect(
        tester.widget<Text>(find.text('Delete deck')).style?.color,
        colors.dontKnowText,
      );
      expect(
        tester.widget<Text>(find.text('Rename')).style?.color,
        isNot(colors.dontKnowText),
      );
      await screens.close();
    },
  );

  testWidgets('without photo import, Add card opens the editor at once', (
    tester,
  ) async {
    final screens = await DeckScreens.open(tester);
    await screens.push((deck) => DeckScreen(deck: deck));

    await screens.tap(find.text('Add card'));

    expect(find.text('Take photo'), findsNothing);
    expect(find.widgetWithText(AppBar, 'Add card'), findsOneWidget);
    await screens.close();
  });

  testWidgets(
    'with photo import, Add card offers by hand, the camera and the album in one sheet, named as the new-deck sheet names them, each photo row opening photo import for this deck from its source',
    (tester) async {
      final screens = await DeckScreens.open(tester, photoImport: true);
      await screens.push((deck) => DeckScreen(deck: deck));

      for (final (row, origin) in [
        ('Take photo', PhotoOrigin.camera),
        ('Choose from album', PhotoOrigin.album),
      ]) {
        await screens.tap(find.text('Add card'));
        expect(find.text('Create by hand'), findsOneWidget);
        expect(find.text('Take photo'), findsOneWidget);
        expect(find.text('Choose from album'), findsOneWidget);
        await screens.tap(find.text(row));
        expect(find.text('photo import'), findsOneWidget);
        expect(screens.photoImports.last, (screens.deck.id, origin));
        screens.navigator.currentState!.pop();
        await tester.pumpAndSettle();
      }
      // By hand opens the editor.
      await screens.tap(find.text('Add card'));
      await screens.tap(find.text('Create by hand'));
      expect(find.widgetWithText(AppBar, 'Add card'), findsOneWidget);
      await screens.close();
    },
  );

  testWidgets(
    'a photo import into another deck replaces this list with that deck, and one into this deck returns here',
    (tester) async {
      final screens = await DeckScreens.open(tester, photoImport: true);
      final other = (await tester.runAsync(
        () => screens.repository.createDeck('Spanish'),
      ))!;
      await screens.push((deck) => DeckScreen(deck: deck));

      Future<void> saveInto(Deck deck) async {
        await screens.tap(find.text('Add card'));
        await screens.tap(find.text('Take photo'));
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
    'a rename stored while the screen is open, as a sync lands one, shows in the title, the rename sheet, the delete question and the editor',
    (tester) async {
      final screens = await DeckScreens.open(tester);
      await screens.push((deck) => DeckScreen(deck: deck));
      expect(find.text('French'), findsOneWidget, reason: 'the opening name');

      await tester.runAsync(
        () => screens.repository.renameDeck(screens.deck.id, 'Français'),
      );
      await tester.pumpAndSettle();
      expect(find.text('Français'), findsOneWidget);
      expect(find.text('French'), findsNothing);

      await screens.tap(find.byTooltip('Deck actions'));
      await screens.tap(find.text('Rename'));
      expect(
        tester
            .widget<EditableText>(
              find.descendant(
                of: find.widgetWithText(AppTextField, 'Deck name'),
                matching: find.byType(EditableText),
              ),
            )
            .controller
            .text,
        'Français',
      );
      await tester.tapAt(const Offset(20, 100));
      await tester.pumpAndSettle();

      await screens.tap(find.byTooltip('Deck actions'));
      await screens.tap(find.text('Delete deck'));
      expect(
        find.byWidgetPredicate(
          (widget) =>
              widget is Text &&
              widget.data?.replaceAll('\u2060', '') == 'Delete "Français"?',
        ),
        findsOneWidget,
      );
      await screens.tap(find.text('Cancel'));

      await screens.tap(find.text('Add card'));
      expect(find.text('Français'), findsOneWidget, reason: "the editor's");
      expect(find.text('French'), findsNothing);
      await screens.close();
    },
  );

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
      expect(
        find.byWidgetPredicate(
          (widget) =>
              widget is Text &&
              widget.data?.replaceAll('\u2060', '') ==
                  'Its 3 cards will be deleted too.',
        ),
        findsOneWidget,
      );
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
