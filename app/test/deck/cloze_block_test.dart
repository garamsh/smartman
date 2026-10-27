import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:flutter/material.dart' hide Card;
import 'package:flutter_test/flutter_test.dart';
import 'package:smartman/deck/deck.dart';
import 'package:smartman/deck/src/block_list.dart';
import 'package:smartman/deck/src/card_preview_screen.dart';
import 'package:smartman/design/app_button.dart';
import 'package:smartman/design/theme.dart';

import '../contrast.dart';
import '../home/deck_screens.dart';
import '../word_breaks.dart';
import 'editor.dart';

/// The stored card, front and back.
Future<Card> _stored(DeckScreens screens) async =>
    (await screens.cards()).single;

/// The line: the first field of the front's blocks.
final _line = blockField(CardSide.front);

/// The line field's controller.
TextEditingController _controller(WidgetTester tester) =>
    tester.widget<TextField>(_line).controller!;

/// The blanks the line draws as blocks, in order: the spans of its text on
/// `brandTint`.
List<String> _blocks(WidgetTester tester) {
  final colors = AppColors.of(tester.element(_line));
  final blocks = <String>[];
  _controller(tester)
      .buildTextSpan(context: tester.element(_line), withComposing: false)
      .visitChildren((child) {
        if (child is TextSpan &&
            child.style?.backgroundColor == colors.brandTint) {
          blocks.add(child.text!);
        }
        return true;
      });
  return blocks;
}

/// The bar's one action while it reads [label].
Finder _action(String label) => find.widgetWithText(ActionChip, label);

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  /// A new card's editor whose front is one Cloze sentence block and whose
  /// back holds none, as a cloze studied on one face needs.
  Future<DeckScreens> openCloze(WidgetTester tester, {DeckScreens? on}) async {
    final screens = on ?? await DeckScreens.open(tester);
    await screens.push((deck) => CardEditorScreen(deck: deck));
    await replaceFirstBlock(screens, CardSide.front, 'Cloze sentence');
    await actOnBlock(screens, CardSide.back, 1, 'Delete');
    return screens;
  }

  Future<void> typeLine(WidgetTester tester, String line) async {
    await tester.ensureVisible(_line);
    await tester.enterText(_line, line);
    await tester.pump();
  }

  /// Selects [start] to [end] of the line, or puts the cursor at [start],
  /// the line focused, as a tap into it leaves it.
  Future<void> select(WidgetTester tester, int start, [int? end]) async {
    await tester.showKeyboard(_line);
    _controller(tester).selection = TextSelection(
      baseOffset: start,
      extentOffset: end ?? start,
    );
    await tester.pump();
  }

  /// Types into the focused line as the keyboard does: [text], the cursor
  /// after [cursor].
  Future<void> typeAt(WidgetTester tester, String text, int cursor) async {
    tester.testTextInput.updateEditingValue(
      TextEditingValue(
        text: text,
        selection: TextSelection.collapsed(offset: cursor),
      ),
    );
    await tester.pump();
  }

  Future<void> insertBlank(DeckScreens screens) =>
      screens.tap(find.text('Insert blank'));

  Future<void> save(DeckScreens screens) async {
    await screens.tester.ensureVisible(find.text('Save'));
    await screens.tap(find.text('Save'));
  }

  testWidgets(
    'Insert blank makes exactly the selected characters a blank, digits, subscripts and particles included, and the card reopens unchanged when saved as it was',
    (tester) async {
      final screens = await openCloze(tester);
      await typeLine(tester, 'H₂O예요');
      await select(tester, 0, 3);
      await insertBlank(screens);
      expect(_blocks(tester), ['H₂O']);
      await save(screens);
      final card = await _stored(screens);
      expect(card.front, [
        const ClozeContent('___예요', ['H₂O']),
      ]);
      expect(card.back, isEmpty, reason: 'a back is the blocks listed on it');

      await screens.push((deck) => CardEditorScreen(deck: deck, card: card));
      expect(_blocks(tester), ['H₂O'], reason: 'opens with its blank');
      await save(screens);
      expect((await _stored(screens)).front, card.front, reason: 'unchanged');

      await openCloze(tester, on: screens);
      await typeLine(tester, '서울은 한국의 수도예요');
      await select(tester, 0, 2);
      await insertBlank(screens);
      await save(screens);
      final cards = await screens.cards();
      expect(
        cards.map((card) => card.front.single),
        contains(const ClozeContent('___은 한국의 수도예요', ['서울'])),
        reason: 'the particle stays outside',
      );
      await screens.close();
    },
  );

  testWidgets(
    'Insert blank with no selection opens an empty blank at the cursor, what is typed into it becomes its answer, and one left empty goes',
    (tester) async {
      final screens = await openCloze(tester);
      await typeLine(tester, '물은 예요');
      await select(tester, 3);
      await insertBlank(screens);
      expect(
        _action('Undo blank'),
        findsOneWidget,
        reason: 'the caret is in the empty blank',
      );
      await typeAt(tester, '물은 H예요', 4);
      await typeAt(tester, '물은 H₂예요', 5);
      await typeAt(tester, '물은 H₂O예요', 6);
      expect(_blocks(tester), ['H₂O']);
      // The cursor leaves it: typing there is text again.
      await select(tester, 0);
      await typeAt(tester, '그 물은 H₂O예요', 2);
      await save(screens);
      expect((await _stored(screens)).front, [
        const ClozeContent('그 물은 ___예요', ['H₂O']),
      ]);

      await openCloze(tester, on: screens);
      await typeLine(tester, 'one two');
      await select(tester, 3);
      await insertBlank(screens);
      expect(_action('Undo blank'), findsOneWidget);
      await select(tester, 0);
      // Back where it was: no blank there any more.
      await select(tester, 3);
      expect(
        _action('Insert blank'),
        findsOneWidget,
        reason: 'left with nothing typed into it, it goes',
      );
      await screens.close();
    },
  );

  testWidgets(
    'the one action follows the caret: inside a blank it reads Undo blank, is named for a screen reader with that blank, and turns exactly that blank into text; elsewhere it reads Insert blank',
    (tester) async {
      final screens = await openCloze(tester);
      await typeLine(tester, 'a cat and a dog');
      await select(tester, 2, 5);
      await insertBlank(screens);
      await select(tester, 12, 15);
      await insertBlank(screens);
      expect(_blocks(tester), ['cat', 'dog']);

      await select(tester, 7);
      expect(_action('Insert blank'), findsOneWidget, reason: 'outside');
      expect(_action('Undo blank'), findsNothing);

      final handle = tester.ensureSemantics();
      await select(tester, 3);
      expect(_action('Undo blank'), findsOneWidget, reason: 'inside cat');
      expect(_action('Insert blank'), findsNothing);
      expect(find.bySemanticsLabel('Undo blank, cat'), findsOneWidget);
      await select(tester, 2, 5);
      expect(
        find.bySemanticsLabel('Undo blank, cat'),
        findsOneWidget,
        reason: 'the whole blank selected',
      );
      handle.dispose();

      await screens.tap(_action('Undo blank'));
      expect(_blocks(tester), ['dog'], reason: 'exactly that blank goes');
      expect(_controller(tester).text, 'a cat and a dog');
      await save(screens);
      expect((await _stored(screens)).front, [
        const ClozeContent('a cat and a ___', ['dog']),
      ]);
      await screens.close();
    },
  );

  testWidgets(
    'the word chips, Pick letters, the blank list, the hint and any row of blank chips are gone, and the line draws its blanks as blocks in place',
    (tester) async {
      final screens = await openCloze(tester);
      await typeLine(tester, 'The cat sat');
      expect(find.byType(FilterChip), findsNothing);
      expect(find.text('Tap the words to make blanks'), findsNothing);
      await select(tester, 4, 7);
      await insertBlank(screens);
      expect(find.text('Pick letters'), findsNothing);
      expect(find.textContaining('Blank 1'), findsNothing);
      expect(find.byType(InputChip), findsNothing, reason: 'no chip row');
      expect(_blocks(tester), ['cat']);
      await screens.close();
    },
  );

  for (final mode in [ThemeMode.light, ThemeMode.dark]) {
    testWidgets(
      'in the ${mode.name} theme the preview draws the cloze whole on one face, each blank a block with its answer, an empty one included',
      (tester) async {
        final screens = await DeckScreens.open(tester, themeMode: mode);
        await openCloze(tester, on: screens);
        await typeLine(tester, 'The cat sat');
        await select(tester, 4, 7);
        await insertBlank(screens);
        await select(tester, 11);
        await insertBlank(screens);
        await screens.tap(find.text('Preview'));
        final preview = find.byType(CardPreviewScreen);
        expect(
          find.descendant(of: preview, matching: find.byType(WholeCardView)),
          findsOneWidget,
        );
        expect(
          find.descendant(of: preview, matching: find.byType(VerticalDivider)),
          findsNothing,
          reason: 'one face, no split card',
        );
        expect(find.text('Front'), findsNothing, reason: 'one face: no side');
        // The blanks as blocks of their answers on brandTint.
        List<String> blocks() {
          final colors = AppColors.of(tester.element(preview));
          final blocks = <String>[];
          for (final paragraph in tester.widgetList<RichText>(
            find.descendant(of: preview, matching: find.byType(RichText)),
          )) {
            paragraph.text.visitChildren((span) {
              if (span is TextSpan &&
                  span.style?.backgroundColor == colors.brandTint) {
                blocks.add(span.text!.trim());
              }
              return true;
            });
          }
          return blocks;
        }

        expect(blocks(), isEmpty, reason: 'the blanks empty, as study asks');
        expect(shownText('Tap the card to fill in its blanks'), findsOneWidget);
        await screens.tap(preview);
        expect(blocks(), ['cat', '']);
        expect(shownText('Tap again to empty its blanks'), findsOneWidget);
        await screens.close();
      },
    );
  }

  testWidgets(
    'typing elsewhere in the line keeps the blanks, and a blank the edit changes is left out',
    (tester) async {
      final screens = await openCloze(tester);
      await typeLine(tester, 'a cat and a dog');
      await select(tester, 10, 11);
      await insertBlank(screens);
      await select(tester, 2, 5);
      await insertBlank(screens);
      await select(tester, 12, 15);
      await insertBlank(screens);
      // The first "a" becomes "one", "cat" becomes "cot", and "big" comes in.
      await typeLine(tester, 'one cat and a dog');
      await typeLine(tester, 'one cot and a dog');
      await typeLine(tester, 'one cot and a big dog');
      expect(_blocks(tester), ['a', 'dog'], reason: 'a changed blank goes');
      await save(screens);
      expect((await _stored(screens)).front, [
        const ClozeContent('one cot and ___ big ___', ['a', 'dog']),
      ]);
      await screens.close();
    },
  );

  testWidgets(
    'a line with no blank is refused with a message under it, and saves once one is inserted',
    (tester) async {
      final screens = await openCloze(tester);
      await typeLine(tester, 'The cat sat');
      await save(screens);
      expect(find.text('Insert at least one blank'), findsOneWidget);
      expect(find.byType(SnackBar), findsNothing);
      expect(await screens.cards(), isEmpty);

      await select(tester, 8, 11);
      await insertBlank(screens);
      expect(find.text('Insert at least one blank'), findsNothing);
      await save(screens);
      expect((await _stored(screens)).front, [
        const ClozeContent('The cat ___', ['sat']),
      ], reason: 'control: with a blank, it saves');
      await screens.close();
    },
  );

  testWidgets(
    'a stored blank inside a word is kept through a save and an edit elsewhere',
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
      expect(_blocks(tester), ['believ']);
      await save(screens);
      expect((await _stored(screens)).front, [cloze]);

      await screens.push((deck) => CardEditorScreen(deck: deck, card: card));
      await select(tester, 0, 2);
      await insertBlank(screens);
      await save(screens);
      expect((await _stored(screens)).front, [
        const ClozeContent('___ is un___able', ['It', 'believ']),
      ], reason: 'another blank added, the stored one keeps its letters');
      await screens.close();
    },
  );

  testWidgets(
    'an imported list cloze keeps its four blanks through a fix elsewhere in the line',
    (tester) async {
      final screens = await DeckScreens.open(tester);
      const answers = ['자기', '자신', '저', '저희'];
      await tester.runAsync(
        () => screens.repository.addCard(
          screens.deck.id,
          front: [const ClozeContent('3인칭 재귀칭: ___, ___, ___, ___', answers)],
          back: [const TextContent('3인칭 재귀칭: 자기, 자신, 저, 저희')],
        ),
      );
      final card = await _stored(screens);
      await screens.push((deck) => CardEditorScreen(deck: deck, card: card));
      await typeLine(tester, '3인칭 재귀칭 : 자기, 자신, 저, 저희');
      await save(screens);
      expect((await _stored(screens)).front, [
        const ClozeContent('3인칭 재귀칭 : ___, ___, ___, ___', answers),
      ]);
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
      await select(tester, 5, 8);
      await insertBlank(screens);
      await save(screens);
      expect(find.text('Add anyway'), findsOneWidget);
      expect((await screens.cards()).length, 1);
      await screens.close();
    },
  );

  testWidgets(
    'a new line holding ___ or a longer run of underscores is refused with a message under it, and the deck still lists',
    (tester) async {
      final screens = await openCloze(tester);
      for (final line in ['capital ___ Paris', 'capital ____ Paris']) {
        await typeLine(tester, line);
        await select(tester, line.length - 5, line.length);
        // The second line keeps the first one's blank on "Paris".
        if (_action('Insert blank').evaluate().isNotEmpty) {
          await insertBlank(screens);
        }
        await save(screens);
        expect(
          find.text('Remove ___ from the line'),
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
      expect(find.text('Remove ___ from the line'), findsOneWidget);
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

  testWidgets(
    'while the line has focus its action is an outlined chip under it, so the editor shows one primary fill, inside a blank and outside one',
    (tester) async {
      final screens = await openCloze(tester);
      await typeLine(tester, 'The cat sat');
      Iterable<AppButton> primaries() => tester
          .widgetList<AppButton>(find.byType(AppButton))
          .where((button) => button.variant == AppButtonVariant.primary);
      for (final (start, end, action) in [
        (4, 7, 'Insert blank'),
        (5, 5, 'Undo blank'),
      ]) {
        await select(tester, start, end);
        if (action == 'Undo blank') {
          // Inside the blank "cat", made by the first round.
          expect(_blocks(tester), ['cat'], reason: 'the setup: a blank');
        }
        // Control: the action is on screen.
        expect(_action(action), findsOneWidget, reason: action);
        expect(
          [for (final button in primaries()) button.label],
          ['Save and next card'],
          reason: action,
        );
        // Right under the line, not in a bar over the keyboard.
        expect(
          tester.getTopLeft(_action(action)).dy,
          greaterThan(tester.getBottomLeft(_line).dy - 1),
          reason: action,
        );
        if (action == 'Insert blank') await insertBlank(screens);
      }
      await screens.close();
    },
  );

  testWidgets(
    'a card with a cloze and nothing on its back says the back may stay empty, and says nothing once the back holds text',
    (tester) async {
      const hint =
          'A card with blanks is answered on its front. Its back can stay empty.';
      // Control: a card of two sides with its back empty is not told so.
      final screens = await DeckScreens.open(tester);
      await screens.push((deck) => CardEditorScreen(deck: deck));
      await typeBlock(tester, CardSide.front, 'Chat');
      expect(shownText(hint), findsNothing, reason: 'control: no cloze');
      await screens.tap(find.byTooltip('Close'));
      await screens.tap(find.text('Discard'));

      await openCloze(tester, on: screens);
      await typeLine(tester, 'The cat sat');
      await select(tester, 4, 7);
      await insertBlank(screens);
      expect(shownText(hint), findsOneWidget);
      await addBlock(screens, CardSide.back, 'Text');
      await typeBlock(tester, CardSide.back, 'A cat sat');
      expect(shownText(hint), findsNothing);
      await screens.close();
    },
  );

  for (final mode in [ThemeMode.light, ThemeMode.dark]) {
    testWidgets(
      'in the ${mode.name} theme a Cloze sentence block meets the tap target, label and contrast guidelines',
      (tester) async {
        final screens = await DeckScreens.open(tester, themeMode: mode);
        await openCloze(tester, on: screens);
        await typeLine(tester, 'The cat sat');
        await select(tester, 4, 7);
        await insertBlank(screens);
        final handle = tester.ensureSemantics();
        await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
        await expectLater(tester, meetsGuideline(iOSTapTargetGuideline));
        await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
        await expectLater(tester, meetsGuideline(textContrastGuideline));
        expectScreenTextReadable(tester);
        handle.dispose();
        await screens.close();
      },
    );
  }
}
