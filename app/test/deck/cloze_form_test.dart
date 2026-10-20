import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:flutter/material.dart' hide Card;
import 'package:flutter_test/flutter_test.dart';
import 'package:smartman/deck/deck.dart';
import 'package:smartman/design/app_text_field.dart';
import 'package:smartman/design/theme.dart';
import 'package:smartman/deck/src/card_preview.dart';

import '../home/deck_screens.dart';

/// The [index]th word button reading [word].
Finder _word(String word, [int index = 0]) =>
    find.widgetWithText(FilterChip, word).at(index);

/// The stored card, front and back.
Future<Card> _stored(DeckScreens screens) async =>
    (await screens.cards()).single;

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  Future<DeckScreens> openCloze(WidgetTester tester, {DeckScreens? on}) async {
    final screens = on ?? await DeckScreens.open(tester);
    await screens.push((deck) => CardEditorScreen(deck: deck));
    await screens.tap(find.text('Sentence'));
    return screens;
  }

  Future<void> typeLine(WidgetTester tester, String line) async {
    final field = find.widgetWithText(AppTextField, 'Front');
    await tester.ensureVisible(field);
    await tester.enterText(field, line);
    await tester.pump();
  }

  /// Taps the [index]th word button reading [word] once it is scrolled into
  /// view.
  Future<void> toggle(DeckScreens screens, String word, [int index = 0]) async {
    await screens.tester.ensureVisible(_word(word, index));
    await screens.tap(_word(word, index));
  }

  Future<void> save(DeckScreens screens) async {
    await screens.tester.ensureVisible(find.text('Save'));
    await screens.tap(find.text('Save'));
  }

  bool chosen(WidgetTester tester, String word) =>
      tester.widget<FilterChip>(_word(word)).selected;

  testWidgets(
    'a cloze saves its line with each run of adjacent chosen words as one blank, its back filled, and reopens unchanged when saved as it was',
    (tester) async {
      final screens = await openCloze(tester);
      await typeLine(tester, 'The cat sat on the mat');
      expect(find.text('Tap the words to make blanks'), findsOneWidget);
      await toggle(screens, 'cat');
      await toggle(screens, 'on');
      await toggle(screens, 'the');
      await toggle(screens, 'mat');
      await toggle(screens, 'mat');
      expect(chosen(tester, 'mat'), isFalse, reason: 'a second tap leaves out');

      final handle = tester.ensureSemantics();
      expect(find.bySemanticsLabel('cat, blank'), findsOneWidget);
      expect(find.bySemanticsLabel('sat'), findsOneWidget);
      handle.dispose();

      await save(screens);
      const cloze = ClozeContent('The ___ sat ___ mat', ['cat', 'on the']);
      final card = await _stored(screens);
      expect(card.front, [cloze]);
      expect(card.back, [const TextContent('The cat sat on the mat')]);

      await screens.push((deck) => CardEditorScreen(deck: deck, card: card));
      expect(find.text('Basic'), findsNothing, reason: 'no switch on edit');
      expect(chosen(tester, 'cat'), isTrue);
      expect(chosen(tester, 'on'), isTrue);
      expect(chosen(tester, 'sat'), isFalse);
      await save(screens);
      expect((await _stored(screens)).front, [cloze], reason: 'a round trip');
      await screens.close();
    },
  );

  testWidgets(
    'typing elsewhere in the line keeps the chosen words, and a chosen word that is changed is left out',
    (tester) async {
      final screens = await openCloze(tester);
      await typeLine(tester, 'a cat and a dog');
      await toggle(screens, 'a', 1);
      await toggle(screens, 'cat');
      await toggle(screens, 'dog');
      // The first "a" becomes "one", "cat" becomes "cats", and "big" comes in.
      await typeLine(tester, 'one cat and a dog');
      await typeLine(tester, 'one cats and a dog');
      await typeLine(tester, 'one cats and a big dog');
      expect(chosen(tester, 'a'), isTrue);
      expect(chosen(tester, 'dog'), isTrue);
      expect(chosen(tester, 'cats'), isFalse, reason: 'a changed word goes');
      await save(screens);
      expect((await _stored(screens)).front, [
        const ClozeContent('one cats and ___ big ___', ['a', 'dog']),
      ]);
      await screens.close();
    },
  );

  testWidgets(
    'a line with no blank is refused with a message under its words, and saves once one is chosen',
    (tester) async {
      final screens = await openCloze(tester);
      await typeLine(tester, 'The cat sat');
      await save(screens);
      expect(find.text('Choose at least one word as a blank'), findsOneWidget);
      expect(find.byType(SnackBar), findsNothing);
      expect(await screens.cards(), isEmpty);

      await toggle(screens, 'sat');
      expect(
        find.text('Choose at least one word as a blank'),
        findsNothing,
        reason: 'chosen, the message goes',
      );
      await save(screens);
      expect((await _stored(screens)).front, [
        const ClozeContent('The cat ___', ['sat']),
      ], reason: 'control: with a blank, it saves');
      await screens.close();
    },
  );

  testWidgets(
    'a stored blank inside a word is kept while the line is left as it was, and the word it falls in is shown chosen',
    (tester) async {
      final screens = await DeckScreens.open(tester);
      const cloze = ClozeContent('It is un___able', ['believ']);
      await tester.runAsync(
        () => screens.repository.addCard(
          screens.deck.id,
          front: [cloze],
          back: [const TextContent('It is unbelievable')],
        ),
      );
      final card = await _stored(screens);
      await screens.push((deck) => CardEditorScreen(deck: deck, card: card));
      expect(chosen(tester, 'unbelievable'), isTrue);
      await save(screens);
      expect((await _stored(screens)).front, [cloze]);

      await screens.push((deck) => CardEditorScreen(deck: deck, card: card));
      await toggle(screens, 'It');
      await save(screens);
      expect((await _stored(screens)).front, [
        const ClozeContent('___ is ___', ['It', 'unbelievable']),
      ], reason: 'edited, the blanks are whole words');
      await screens.close();
    },
  );

  testWidgets(
    'a cloze whose filled line is already a card opens the duplicate sheet',
    (tester) async {
      final screens = await DeckScreens.open(
        tester,
        cards: {'The cat sat': '고양이가 앉았다'},
      );
      await openCloze(tester, on: screens);
      await typeLine(tester, ' the cat sat ');
      await toggle(screens, 'cat');
      await save(screens);
      expect(find.text('Add anyway'), findsOneWidget);
      expect((await screens.cards()).length, 1);
      await screens.close();
    },
  );

  testWidgets(
    'a new line holding ___ or a longer run of underscores is refused with a message under its words, and the deck still lists',
    (tester) async {
      final screens = await openCloze(tester);
      for (final line in ['capital ___ Paris', 'capital ____ Paris']) {
        await typeLine(tester, line);
        if (!chosen(tester, 'Paris')) await toggle(screens, 'Paris');
        await save(screens);
        expect(
          find.text("___ marks a blank, so the line can't contain it"),
          findsOneWidget,
          reason: line,
        );
        expect(find.byType(SnackBar), findsNothing);
        expect(await screens.cards(), isEmpty, reason: 'it lists, empty');
      }

      await typeLine(tester, 'capital of France Paris');
      await save(screens);
      expect((await _stored(screens)).front, [
        const ClozeContent('capital of France ___', ['Paris']),
      ], reason: 'control: without the underscores, it saves');
      await screens.close();
    },
  );

  testWidgets(
    'an edit of a stored cloze that types ___ into its line is refused, the card is kept as stored, and the deck still lists',
    (tester) async {
      final screens = await DeckScreens.open(tester);
      const cloze = ClozeContent('a ___ b', ['x']);
      await tester.runAsync(
        () => screens.repository.addCard(
          screens.deck.id,
          front: [cloze],
          back: [const TextContent('a x b')],
        ),
      );
      final card = await _stored(screens);
      await screens.push((deck) => CardEditorScreen(deck: deck, card: card));
      await typeLine(tester, 'a x b ___ c');
      await save(screens);
      expect(
        find.text("___ marks a blank, so the line can't contain it"),
        findsOneWidget,
      );
      expect(find.byType(SnackBar), findsNothing);
      expect((await _stored(screens)).front, [cloze]);

      await typeLine(tester, 'a x b c');
      await save(screens);
      expect((await _stored(screens)).front, [
        const ClozeContent('a ___ b c', ['x']),
      ], reason: 'control: without the underscores, the edit saves');
      await screens.close();
    },
  );

  for (final mode in [ThemeMode.light, ThemeMode.dark]) {
    testWidgets(
      'in the ${mode.name} theme a chosen word is drawn in the colour of the preview\'s blank, and before any blank the preview draws the line whole',
      (tester) async {
        final screens = await DeckScreens.open(tester, themeMode: mode);
        await openCloze(tester, on: screens);
        await typeLine(tester, 'The cat sat');
        final preview = find.byType(CardPreview);
        expect(
          find.descendant(of: preview, matching: find.byType(WholeCardView)),
          findsOneWidget,
          reason: 'whole, not the line on both halves',
        );
        expect(
          find.descendant(of: preview, matching: find.byType(VerticalDivider)),
          findsNothing,
          reason: 'no split card, whose halves a divider parts',
        );

        await toggle(screens, 'cat');
        final colors = AppColors.of(tester.element(_word('cat')));
        expect(
          tester.widget<FilterChip>(_word('cat')).selectedColor,
          colors.brandTint,
        );
        Color? blankFill;
        for (final paragraph in tester.widgetList<RichText>(
          find.descendant(of: preview, matching: find.byType(RichText)),
        )) {
          paragraph.text.visitChildren((span) {
            if (span is TextSpan && span.text?.trim() == 'cat') {
              blankFill = span.style?.backgroundColor;
            }
            return true;
          });
        }
        expect(blankFill, colors.brandTint, reason: 'the preview draws it so');
        await screens.close();
      },
    );
  }

  for (final mode in [ThemeMode.light, ThemeMode.dark]) {
    testWidgets(
      'in the ${mode.name} theme the cloze form meets the tap target, label and contrast guidelines',
      (tester) async {
        final screens = await DeckScreens.open(tester, themeMode: mode);
        await openCloze(tester, on: screens);
        await typeLine(tester, 'The cat sat on the mat');
        final handle = tester.ensureSemantics();
        Future<void> meetsGuidelines() async {
          await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
          await expectLater(tester, meetsGuideline(iOSTapTargetGuideline));
          await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
          await expectLater(tester, meetsGuideline(textContrastGuideline));
        }

        // With the message for a missing blank, then with a word chosen.
        await save(screens);
        expect(
          find.text('Choose at least one word as a blank'),
          findsOneWidget,
        );
        await meetsGuidelines();
        await toggle(screens, 'cat');
        await meetsGuidelines();
        handle.dispose();
        await screens.close();
      },
    );
  }
}
