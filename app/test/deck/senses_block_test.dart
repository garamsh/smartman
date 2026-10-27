import 'dart:convert';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:flutter/material.dart' hide Card;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smartman/deck/deck.dart';
import 'package:smartman/deck/src/block_list.dart';
import 'package:smartman/deck/src/editor_group.dart';
import 'package:smartman/deck/src/label_presets.dart';
import 'package:smartman/deck/src/senses_block.dart';
import 'package:smartman/design/app_chip.dart';
import 'package:smartman/design/theme.dart';

import '../contrast.dart';
import '../home/deck_screens.dart';
import 'editor.dart';

/// The [index]th sense's label field.
Finder _labelField([int index = 0]) => find
    .descendant(
      of: find.byType(SenseFields),
      matching: find.byWidgetPredicate(
        (widget) => widget is TextField && widget.textAlign == TextAlign.center,
      ),
    )
    .at(index);

/// The field labelled [label] in the back's blocks.
Finder _back(String label) => labelledField(CardSide.back, label);

/// [blocks] as stored, without the ids a write gives them.
List<Object?> _withoutIds(List<Content> blocks) => [
  for (final block in jsonDecode(encodeContent(blocks)) as List<Object?>)
    {...block! as Map<String, Object?>}..remove('id'),
];

/// The stored card, front and back.
Future<Card> _stored(DeckScreens screens) async =>
    (await screens.cards()).single;

const _noun = PartOfSpeechLabel(PartOfSpeech.noun, '명');

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  /// A new card's editor whose back is one Meanings block.
  Future<DeckScreens> openNew(WidgetTester tester) async {
    final screens = await DeckScreens.open(tester);
    await screens.push((deck) => CardEditorScreen(deck: deck));
    await replaceFirstBlock(screens, CardSide.back, 'Meanings');
    return screens;
  }

  /// [card]'s editor.
  Future<void> openCard(DeckScreens screens, Card card) =>
      screens.push((deck) => CardEditorScreen(deck: deck, card: card));

  testWidgets(
    'a card whose back holds senses opens with them as a Meanings block, each with its label and meaning',
    (tester) async {
      final screens = await DeckScreens.open(tester);
      await tester.runAsync(
        () => screens.repository.addCard(
          screens.deck.id,
          front: [const TextContent('present')],
          back: [
            const SensesContent([
              CardSense(labels: [_noun], meaning: '선물'),
              CardSense(
                labels: [PartOfSpeechLabel(PartOfSpeech.verb, '동')],
                meaning: '주다',
              ),
            ]),
          ],
        ),
      );
      await openCard(screens, await _stored(screens));
      expect(
        find.descendant(
          of: blockList(CardSide.back),
          matching: find.text('Meanings'),
        ),
        findsOneWidget,
      );
      expect(find.byType(SenseFields), findsOneWidget);
      expect(tester.widget<TextField>(_labelField()).controller!.text, '명');
      expect(tester.widget<TextField>(_labelField(1)).controller!.text, '동');
      expect(_back('Meaning 1'), findsOneWidget);
      expect(_back('Meaning 2'), findsOneWidget);
      await screens.close();
    },
  );

  testWidgets(
    'a Meanings block is saved as senses, one meaning without a label included, and a Text block as text',
    (tester) async {
      final screens = await openNew(tester);
      await typeBlock(tester, CardSide.front, 'cat');
      await typeInto(tester, _back('Meaning'), '고양이');
      await tapVisible(screens, find.text('Save'));
      expect((await _stored(screens)).back, [
        const SensesContent([CardSense(meaning: '고양이')]),
      ]);

      // Control: the same card with a Text block on its back.
      await screens.push((deck) => CardEditorScreen(deck: deck));
      await typeBlock(tester, CardSide.front, 'dog');
      await typeBlock(tester, CardSide.back, '개');
      await tapVisible(screens, find.text('Save'));
      final dog = (await screens.cards()).singleWhere(
        (card) => card.front.single == const TextContent('dog'),
      );
      expect(dog.back, [const TextContent('개')]);
      await screens.close();
    },
  );

  testWidgets(
    'a stored back of one plain sense, with its extras, stays senses when saved unchanged or edited, not text',
    (tester) async {
      final screens = await DeckScreens.open(tester);
      const extras = TextContent('extras');
      await tester.runAsync(
        () => screens.repository.addCard(
          screens.deck.id,
          front: [const TextContent('face')],
          back: [
            const SensesContent([CardSense(meaning: 'x')]),
            extras,
          ],
        ),
      );
      final card = await _stored(screens);
      expect(card.back, [
        const SensesContent([CardSense(meaning: 'x')]),
        extras,
      ], reason: 'the setup stores the back asked');
      await openCard(screens, card);
      await tapVisible(screens, find.text('Save'));
      expect((await _stored(screens)).back, [
        const SensesContent([CardSense(meaning: 'x')]),
        extras,
      ], reason: 'saved unchanged');

      await openCard(screens, await _stored(screens));
      await typeInto(tester, _back('Meaning'), 'y');
      await tapVisible(screens, find.text('Save'));
      expect((await _stored(screens)).back, [
        const SensesContent([CardSense(meaning: 'y')]),
        extras,
      ], reason: 'edited, still senses with its extras');
      await screens.close();
    },
  );

  testWidgets(
    'a typed label is saved as a part of speech when it is a short form and as another label otherwise, and a label left as it was keeps the text it was stored with',
    (tester) async {
      final screens = await openNew(tester);
      await typeBlock(tester, CardSide.front, 'present');
      await typeInto(tester, _labelField(), '[명]');
      await typeInto(tester, _back('Meaning'), '선물');
      await tapVisible(screens, find.bySemanticsLabel('Add meaning'));
      await typeInto(tester, _labelField(1), '고어 object');
      await typeInto(tester, _back('Meaning 2'), '주다');
      await tapVisible(screens, find.text('Save'));
      expect((await _stored(screens)).back, [
        const SensesContent([
          CardSense(labels: [_noun], meaning: '선물'),
          CardSense(
            labels: [OtherLabel('고어'), OtherLabel('object')],
            meaning: '주다',
          ),
        ]),
      ]);
      await screens.close();
    },
  );

  testWidgets(
    'a stored label printed in another form keeps its text while left as it was, and becomes the short form once retyped',
    (tester) async {
      final screens = await DeckScreens.open(tester);
      const printed = SensesContent([
        CardSense(
          labels: [PartOfSpeechLabel(PartOfSpeech.noun, 'n')],
          meaning: '얼굴',
        ),
      ]);
      await tester.runAsync(
        () => screens.repository.addCard(
          screens.deck.id,
          front: [const TextContent('face')],
          back: [printed],
        ),
      );
      await openCard(screens, await _stored(screens));
      expect(
        tester.widget<TextField>(_labelField()).controller!.text,
        '명',
        reason: 'shown as its short form',
      );
      await tapVisible(screens, find.text('Save'));
      expect((await _stored(screens)).back, [printed], reason: 'as stored');

      await openCard(screens, await _stored(screens));
      await typeInto(tester, _labelField(), '명 ');
      await tapVisible(screens, find.text('Save'));
      expect((await _stored(screens)).back, [
        const SensesContent([
          CardSense(labels: [_noun], meaning: '얼굴'),
        ]),
      ], reason: 'retyped, the short form');
      await screens.close();
    },
  );

  testWidgets(
    'a sense\'s label is a chip a line high, as wide as its text, on its meaning\'s baseline, and a tap beside it still edits it',
    (tester) async {
      final screens = await DeckScreens.open(tester);
      await tester.runAsync(
        () => screens.repository.addCard(
          screens.deck.id,
          front: [const TextContent('present')],
          back: [
            const SensesContent([
              CardSense(labels: [_noun], meaning: '선물'),
              CardSense(
                labels: [
                  PartOfSpeechLabel(PartOfSpeech.verb, '동'),
                  OtherLabel('격식'),
                ],
                meaning: '주다',
              ),
            ]),
          ],
        ),
      );
      await openCard(screens, await _stored(screens));
      final short = tester.getRect(_labelField());
      final long = tester.getRect(_labelField(1));
      expect(short.height, labelChipHeight, reason: 'a line of body text');
      expect(short.height, lessThan(AppSize.tapTarget));
      expect(
        long.width,
        greaterThan(short.width + 20),
        reason: 'as wide as its text, not one width for every label',
      );
      expect(short.width, lessThan(64));

      // The chip's text and its meaning's sit on one baseline: both are lines
      // of 16/24 text, so their lines start level.
      double line(Finder field) => tester
          .getTopLeft(
            find.descendant(of: field, matching: find.byType(EditableText)),
          )
          .dy;
      expect(line(_labelField()), closeTo(line(_back('Meaning 1')), 0.5));

      // Its tap target is a target square, though the chip is smaller.
      final handle = tester.ensureSemantics();
      final target = tester.getSemantics(_labelField()).rect;
      expect(target.height, greaterThanOrEqualTo(kMinInteractiveDimension));
      expect(target.width, greaterThanOrEqualTo(kMinInteractiveDimension));
      handle.dispose();
      await tester.tapAt(short.topCenter - const Offset(0, 6));
      await tester.pumpAndSettle();
      expect(
        tester.widget<TextField>(_labelField()).focusNode!.hasFocus,
        isTrue,
        reason: 'a tap just above the chip focuses it',
      );
      expect(find.byType(LabelPresetStrip), findsOneWidget);
      await screens.close();
    },
  );

  testWidgets(
    'the presets show above the keyboard in the user\'s order only while a label field has focus, and a tap fills that field',
    (tester) async {
      final screens = await openNew(tester);
      final storage = ProviderScope.containerOf(
        tester.element(find.byType(CardEditorScreen)),
      ).read(deckStorageProvider);
      await tester.runAsync(
        () => saveLabelPresets(storage, const [
          LabelPreset('숙어', 'idiom'),
          LabelPreset('명', '명사'),
        ]),
      );
      await tester.tap(blockField(CardSide.front));
      await tester.pumpAndSettle();
      expect(find.byType(LabelPresetStrip), findsNothing);
      await tester.tap(_labelField());
      await tester.pumpAndSettle();
      expect(find.byType(LabelPresetStrip), findsOneWidget);
      final chips = tester
          .widgetList<AppChip>(find.byType(AppChip))
          .map((chip) => chip.label)
          .toList();
      expect(chips, ['숙어', '명'], reason: "in the user's order");

      await tester.tap(find.widgetWithText(AppChip, '숙어'));
      await tester.pumpAndSettle();
      final label = tester.widget<TextField>(_labelField());
      expect(label.controller!.text, '숙어');
      expect(
        label.focusNode!.hasFocus,
        isTrue,
        reason: 'the field keeps focus',
      );
      expect(
        tester.widget<AppChip>(find.widgetWithText(AppChip, '숙어')).selected,
        isTrue,
      );

      await tester.tap(blockField(CardSide.front));
      await tester.pumpAndSettle();
      expect(
        find.byType(LabelPresetStrip),
        findsNothing,
        reason: 'control: gone with the focus on another field',
      );
      await screens.close();
    },
  );

  testWidgets(
    'editing a back of senses changes them and keeps any other block of its back, such as its extras',
    (tester) async {
      final screens = await DeckScreens.open(tester);
      const extras = TextContent('유의어 confront');
      await tester.runAsync(
        () => screens.repository.addCard(
          screens.deck.id,
          front: [const TextContent('face')],
          back: [
            const SensesContent([
              CardSense(labels: [_noun], meaning: '얼굴'),
            ]),
            extras,
          ],
        ),
      );
      await openCard(screens, await _stored(screens));
      await typeInto(tester, _back('Meaning'), '얼굴, 표면');
      await tapVisible(screens, find.text('Save'));
      expect((await _stored(screens)).back, [
        const SensesContent([
          CardSense(labels: [_noun], meaning: '얼굴, 표면'),
        ]),
        extras,
      ]);
      await screens.close();
    },
  );

  testWidgets(
    'each text block beside a back\'s senses is a Text block of its own: untouched the back is stored as it was, edited it saves the text, deleted the block goes, and a block of an unknown type stays',
    (tester) async {
      final screens = await DeckScreens.open(tester);
      const senses = SensesContent([
        CardSense(labels: [_noun], meaning: '얼굴', examples: ['a face']),
      ]);
      const unknown = UnsupportedContent('future', {'x': 1});
      final back = <Content>[
        senses,
        const TextContent('유의어 confront'),
        unknown,
        const TextContent('a merged line'),
      ];
      await tester.runAsync(
        () => screens.repository.addCard(
          screens.deck.id,
          front: [const TextContent('face')],
          back: back,
        ),
      );
      final card = await _stored(screens);
      await openCard(screens, card);
      // Each text a Text block's field of its own, beside the senses' block.
      for (final text in ['유의어 confront', 'a merged line']) {
        expect(
          find.descendant(
            of: blockList(CardSide.back),
            matching: find.widgetWithText(TextField, text),
          ),
          findsOneWidget,
          reason: text,
        );
      }
      expect(find.byTooltip('Back block 4 menu'), findsOneWidget);
      expect(
        find.descendant(
          of: blockList(CardSide.back),
          matching: find.text('Examples'),
        ),
        findsOneWidget,
        reason: 'it has examples',
      );
      expect(find.widgetWithText(TextField, '유의어 confront'), findsOneWidget);

      await tapVisible(screens, find.text('Save'));
      expect(
        encodeContent((await _stored(screens)).back),
        encodeContent(card.back),
        reason: 'untouched, stored as it was',
      );

      await openCard(screens, await _stored(screens));
      await typeInto(
        tester,
        find.widgetWithText(TextField, '유의어 confront'),
        '유의어 confront, encounter',
      );
      await actOnBlock(screens, CardSide.back, 4, 'Delete');
      await tapVisible(screens, find.text('Save'));
      expect(
        _withoutIds((await _stored(screens)).back),
        _withoutIds([
          senses,
          const TextContent('유의어 confront, encounter'),
          unknown,
        ]),
      );
      await screens.close();
    },
  );

  testWidgets(
    'a sense without a meaning and an empty front are refused, each with a message on its field',
    (tester) async {
      final screens = await openNew(tester);
      await typeInto(tester, _back('Meaning'), '사과');
      await tapVisible(screens, find.bySemanticsLabel('Add meaning'));
      await tapVisible(screens, find.text('Save'));
      expect(find.text('Enter the meaning'), findsOneWidget);
      expect(find.text('Write something'), findsOneWidget);
      expect(await screens.cards(), isEmpty);

      // The front alone filled: the block refuses the empty meaning itself,
      // without a save that fails.
      await typeBlock(tester, CardSide.front, 'apple');
      await tapVisible(screens, find.text('Save'));
      expect(find.text('Enter the meaning'), findsOneWidget);
      expect(find.text('Write something'), findsNothing);
      expect(find.byType(SnackBar), findsNothing);
      expect(await screens.cards(), isEmpty);

      await typeInto(tester, _back('Meaning 2'), '능금');
      await tapVisible(screens, find.text('Save'));
      expect((await _stored(screens)).back, [
        const SensesContent([
          CardSense(meaning: '사과'),
          CardSense(meaning: '능금'),
        ]),
      ], reason: 'control: filled, it saves');
      await screens.close();
    },
  );

  testWidgets(
    'senses move and are deleted through each one\'s menu, which a block of one meaning has none of, and the one left is hinted Meaning again',
    (tester) async {
      final screens = await openNew(tester);
      await typeBlock(tester, CardSide.front, 'apple');
      await typeInto(tester, _back('Meaning'), 'first');
      await tapVisible(screens, find.bySemanticsLabel('Add meaning'));
      await typeInto(tester, _back('Meaning 2'), 'second');
      await tapVisible(screens, find.bySemanticsLabel('Add meaning'));
      await typeInto(tester, _back('Meaning 3'), 'third');
      await typeInto(tester, _labelField(2), '명');

      // [first, second, third [명]] becomes [first, third [명], second], then
      // [third [명], first, second]; then the third sense goes.
      Future<void> act(int number, String action) async {
        await tapVisible(screens, find.byTooltip('Meaning $number menu'));
        await screens.tap(find.text(action).last);
      }

      await act(3, 'Move up');
      await act(1, 'Move down');
      await act(3, 'Delete');
      await tapVisible(screens, find.text('Save'));
      expect((await _stored(screens)).back, [
        const SensesContent([
          CardSense(labels: [_noun], meaning: 'third'),
          CardSense(meaning: 'first'),
        ]),
      ]);

      // A new block starts as one meaning, with no menu to move or delete it.
      await screens.push((deck) => CardEditorScreen(deck: deck));
      await replaceFirstBlock(screens, CardSide.back, 'Meanings');
      expect(find.byTooltip('Meaning 1 menu'), findsNothing);
      await tapVisible(screens, find.bySemanticsLabel('Add meaning'));
      expect(
        find.byTooltip('Meaning 1 menu'),
        findsOneWidget,
        reason: 'control: with two, either can go',
      );
      await act(2, 'Delete');
      expect(_back('Meaning'), findsOneWidget, reason: 'one meaning again');
      await screens.close();
    },
  );

  testWidgets(
    'a duplicate front opens the duplicate sheet, a back of senses too',
    (tester) async {
      final screens = await DeckScreens.open(tester, cards: {'apple': '사과'});
      await screens.push((deck) => CardEditorScreen(deck: deck));
      await replaceFirstBlock(screens, CardSide.back, 'Meanings');
      await typeBlock(tester, CardSide.front, ' Apple ');
      await typeInto(tester, _labelField(), '명');
      await typeInto(tester, _back('Meaning'), '능금');
      await tapVisible(screens, find.text('Save'));
      expect(find.text('Add anyway'), findsOneWidget);
      expect((await screens.cards()).length, 1);
      await screens.close();
    },
  );

  for (final mode in [ThemeMode.light, ThemeMode.dark]) {
    testWidgets(
      'in the ${mode.name} theme a Meanings block with its senses and presets meets the tap target, label and contrast guidelines',
      (tester) async {
        final screens = await DeckScreens.open(tester, themeMode: mode);
        await screens.push((deck) => CardEditorScreen(deck: deck));
        await replaceFirstBlock(screens, CardSide.back, 'Meanings');
        await tapVisible(screens, find.bySemanticsLabel('Add meaning'));
        await tester.tap(_labelField());
        await tester.pumpAndSettle();
        expect(find.byType(LabelPresetStrip), findsOneWidget);
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
