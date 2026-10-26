import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:flutter/material.dart' hide Card;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smartman/deck/deck.dart';
import 'package:smartman/deck/src/card_kind.dart';
import 'package:smartman/deck/src/label_presets.dart';
import 'package:smartman/deck/src/word_form.dart';
import 'package:smartman/design/app_text_field.dart';

import '../home/deck_screens.dart';

/// The field labelled [label], the [index]th of those on screen.
Finder _field(String label, [int index = 0]) =>
    find.widgetWithText(AppTextField, label).at(index);

/// The [index]th sense's label field.
Finder _labelField([int index = 0]) => find
    .descendant(
      of: find.byType(SenseFields),
      matching: find.byWidgetPredicate(
        (widget) => widget is TextField && widget.textAlign == TextAlign.center,
      ),
    )
    .at(index);

/// The stored card, front and back.
Future<Card> _stored(DeckScreens screens) async =>
    (await screens.cards()).single;

const _noun = PartOfSpeechLabel(PartOfSpeech.noun, '명');

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  Future<DeckScreens> openNew(WidgetTester tester) async {
    final screens = await DeckScreens.open(tester);
    await screens.push((deck) => CardEditorScreen(deck: deck));
    return screens;
  }

  /// Types [text] into [field] once it is scrolled into view.
  Future<void> type(WidgetTester tester, Finder field, String text) async {
    await tester.ensureVisible(field);
    await tester.enterText(field, text);
    await tester.pump();
  }

  /// Types [text] into the [index]th field labelled [label].
  Future<void> enter(
    WidgetTester tester,
    String label,
    String text, [
    int index = 0,
  ]) => type(tester, _field(label, index), text);

  /// Taps [finder] once it is scrolled into view.
  Future<void> tap(DeckScreens screens, Finder finder) async {
    await screens.tester.ensureVisible(finder);
    await screens.tap(finder);
  }

  CardKind shownKind(WidgetTester tester) => tester
      .widget<SegmentedButton<CardKind>>(find.byType(SegmentedButton<CardKind>))
      .selected
      .single;

  testWidgets(
    'the kind switch reads Front & back, Cloze and Table, and a card whose back holds senses opens as basic with its senses',
    (tester) async {
      final screens = await openNew(tester);
      for (final kind in ['Front & back', 'Cloze', 'Table']) {
        expect(find.text(kind), findsOneWidget, reason: kind);
      }
      expect(find.text('Word'), findsNothing, reason: 'no word kind');
      expect(
        tester
            .widget<SegmentedButton<CardKind>>(
              find.byType(SegmentedButton<CardKind>),
            )
            .segments
            .length,
        3,
      );
      await screens.tap(find.byTooltip('Close'));

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
      final card = await _stored(screens);
      await screens.push((deck) => CardEditorScreen(deck: deck, card: card));
      expect(find.byType(SenseFields), findsOneWidget, reason: 'basic form');
      expect(tester.widget<TextField>(_labelField()).controller!.text, '명');
      expect(tester.widget<TextField>(_labelField(1)).controller!.text, '동');
      expect(_field('Meaning 1'), findsOneWidget);
      expect(_field('Meaning 2'), findsOneWidget);
      await screens.close();
    },
  );

  testWidgets(
    'a deck starts its next new card in the kind of the last card added, not of the last switch tapped, and a stored word kind opens as basic',
    (tester) async {
      final screens = await openNew(tester);
      await screens.tap(find.text('Table'));
      // Closed with nothing added: the switch alone is not remembered.
      await screens.tap(find.byTooltip('Close'));
      await screens.push((deck) => CardEditorScreen(deck: deck));
      expect(shownKind(tester), CardKind.basic);

      await screens.tap(find.text('Cloze'));
      await enter(tester, 'Front', 'The cat');
      await tap(screens, find.text('cat'));
      await tap(screens, find.text('Save'));
      await screens.push((deck) => CardEditorScreen(deck: deck));
      expect(
        shownKind(tester),
        CardKind.cloze,
        reason: 'control: a card added is remembered',
      );
      await screens.tap(find.byTooltip('Close'));

      // A device that remembered the word kind ADR 0100 folded into basic.
      final storage = ProviderScope.containerOf(
        tester.element(find.byType(Navigator).first),
      ).read(deckStorageProvider);
      await tester.runAsync(
        () => storage.setString(
          'deckCardKinds',
          '{"${screens.deck.id.value}": "word"}',
        ),
      );
      await screens.push((deck) => CardEditorScreen(deck: deck));
      expect(shownKind(tester), CardKind.basic);
      await screens.close();
    },
  );

  testWidgets(
    'a back of one meaning with no label is saved as text, as a basic card was, and a label, or a second meaning, makes it senses',
    (tester) async {
      final screens = await openNew(tester);
      await enter(tester, 'Front', 'cat');
      await enter(tester, 'Back', '고양이');
      await tap(screens, find.text('Save'));
      final card = await _stored(screens);
      expect(card.back, [const TextContent('고양이')]);

      await screens.push((deck) => CardEditorScreen(deck: deck, card: card));
      await type(tester, _labelField(), '명');
      await tap(screens, find.text('Save'));
      expect((await _stored(screens)).back, [
        const SensesContent([
          CardSense(labels: [_noun], meaning: '고양이'),
        ]),
      ], reason: 'a label makes it senses');

      // A second plain card: a second meaning makes it senses, no label.
      await screens.push((deck) => CardEditorScreen(deck: deck));
      await enter(tester, 'Front', 'dog');
      await enter(tester, 'Back', '개');
      await tap(screens, find.text('Add meaning'));
      await enter(tester, 'Meaning 2', '견');
      await tap(screens, find.text('Save'));
      final dog = (await screens.cards()).singleWhere(
        (card) => card.front.single == const TextContent('dog'),
      );
      expect(dog.back, [
        const SensesContent([CardSense(meaning: '개'), CardSense(meaning: '견')]),
      ], reason: 'a second meaning makes it senses');
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
      await screens.push((deck) => CardEditorScreen(deck: deck, card: card));
      await tap(screens, find.text('Save'));
      expect((await _stored(screens)).back, [
        const SensesContent([CardSense(meaning: 'x')]),
        extras,
      ], reason: 'saved unchanged');

      final saved = await _stored(screens);
      await screens.push((deck) => CardEditorScreen(deck: deck, card: saved));
      await enter(tester, 'Back', 'y');
      await tap(screens, find.text('Save'));
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
      await enter(tester, 'Front', 'present');
      await type(tester, _labelField(), '[명]');
      await enter(tester, 'Back', '선물');
      await tap(screens, find.text('Add meaning'));
      await type(tester, _labelField(1), '고어 object');
      await enter(tester, 'Meaning 2', '주다');
      await tap(screens, find.text('Save'));
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
      final card = await _stored(screens);
      await screens.push((deck) => CardEditorScreen(deck: deck, card: card));
      expect(
        tester.widget<TextField>(_labelField()).controller!.text,
        '명',
        reason: 'shown as its short form',
      );
      await tap(screens, find.text('Save'));
      expect((await _stored(screens)).back, [printed], reason: 'as stored');

      final saved = await _stored(screens);
      await screens.push((deck) => CardEditorScreen(deck: deck, card: saved));
      await type(tester, _labelField(), '명 ');
      await tap(screens, find.text('Save'));
      expect((await _stored(screens)).back, [
        const SensesContent([
          CardSense(labels: [_noun], meaning: '얼굴'),
        ]),
      ], reason: 'retyped, the short form');
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
      expect(find.byType(LabelPresetStrip), findsNothing);
      await tester.tap(_labelField());
      await tester.pumpAndSettle();
      expect(find.byType(LabelPresetStrip), findsOneWidget);
      final chips = tester
          .widgetList<ChoiceChip>(find.byType(ChoiceChip))
          .map((chip) => (chip.label as Text).data)
          .toList();
      expect(chips, ['숙어', '명'], reason: "in the user's order");

      await tester.tap(find.widgetWithText(ChoiceChip, '숙어'));
      await tester.pumpAndSettle();
      final label = tester.widget<TextField>(_labelField());
      expect(label.controller!.text, '숙어');
      expect(
        label.focusNode!.hasFocus,
        isTrue,
        reason: 'the field keeps focus',
      );
      expect(
        tester
            .widget<ChoiceChip>(find.widgetWithText(ChoiceChip, '숙어'))
            .selected,
        isTrue,
      );

      await tester.tap(_field('Front'));
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
      final card = await _stored(screens);
      await screens.push((deck) => CardEditorScreen(deck: deck, card: card));
      await enter(tester, 'Back', '얼굴, 표면');
      await tap(screens, find.text('Save'));
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
    'each text block beside a back\'s senses has a field: untouched the back is stored as it was, edited it saves the text, cleared the block goes, and a block of an unknown type stays',
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
      await screens.push((deck) => CardEditorScreen(deck: deck, card: card));
      expect(_field('More on the back'), findsOneWidget);
      expect(_field('More on the back', 1), findsOneWidget);
      expect(_field('Examples'), findsOneWidget, reason: 'it has examples');
      expect(find.widgetWithText(TextField, '유의어 confront'), findsOneWidget);

      await tap(screens, find.text('Save'));
      expect(
        encodeContent((await _stored(screens)).back),
        encodeContent(back),
        reason: 'untouched, stored as it was',
      );

      final saved = await _stored(screens);
      await screens.push((deck) => CardEditorScreen(deck: deck, card: saved));
      await enter(tester, 'More on the back', '유의어 confront, encounter');
      await enter(tester, 'More on the back', '', 1);
      await tap(screens, find.text('Save'));
      expect(
        encodeContent((await _stored(screens)).back),
        encodeContent([
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
      await enter(tester, 'Back', '사과');
      await tap(screens, find.text('Add meaning'));
      await tap(screens, find.text('Save'));
      expect(find.text('Enter the meaning'), findsOneWidget);
      expect(find.text('Enter some text'), findsOneWidget);
      expect(await screens.cards(), isEmpty);

      // The front alone filled: the form refuses the empty meaning itself,
      // without a save that fails.
      await enter(tester, 'Front', 'apple');
      await tap(screens, find.text('Save'));
      expect(find.text('Enter the meaning'), findsOneWidget);
      expect(find.text('Enter some text'), findsNothing);
      expect(find.byType(SnackBar), findsNothing);
      expect(await screens.cards(), isEmpty);

      await enter(tester, 'Meaning 2', '능금');
      await tap(screens, find.text('Save'));
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
    'senses move by their buttons and are deleted by theirs, and the last one left is the back again',
    (tester) async {
      final screens = await openNew(tester);
      await enter(tester, 'Front', 'apple');
      await enter(tester, 'Back', 'first');
      await tap(screens, find.text('Add meaning'));
      await enter(tester, 'Meaning 2', 'second');
      await tap(screens, find.text('Add meaning'));
      await enter(tester, 'Meaning 3', 'third');
      await type(tester, _labelField(2), '명');

      // [first, second, third [명]] becomes [first, third [명], second], then
      // [third [명], first, second]; then the third sense goes.
      await tap(screens, find.byTooltip('Move meaning 3 up'));
      await tap(screens, find.byTooltip('Move meaning 1 down'));
      await tap(screens, find.byTooltip('Delete meaning 3'));
      await tap(screens, find.text('Save'));
      expect((await _stored(screens)).back, [
        const SensesContent([
          CardSense(labels: [_noun], meaning: 'third'),
          CardSense(meaning: 'first'),
        ]),
      ]);

      // A new card starts as one meaning, with no buttons to move or delete.
      await screens.push((deck) => CardEditorScreen(deck: deck));
      expect(find.byTooltip('Delete meaning 1'), findsNothing);
      await tap(screens, find.text('Add meaning'));
      expect(
        find.byTooltip('Delete meaning 1'),
        findsOneWidget,
        reason: 'control: with two, either can go',
      );
      await tap(screens, find.byTooltip('Delete meaning 2'));
      expect(_field('Back'), findsOneWidget, reason: 'one meaning: the back');
      await screens.close();
    },
  );

  testWidgets(
    'a duplicate front opens the duplicate sheet, a back of senses too',
    (tester) async {
      final screens = await DeckScreens.open(tester, cards: {'apple': '사과'});
      await screens.push((deck) => CardEditorScreen(deck: deck));
      await enter(tester, 'Front', ' Apple ');
      await type(tester, _labelField(), '명');
      await enter(tester, 'Back', '능금');
      await tap(screens, find.text('Save'));
      expect(find.text('Add anyway'), findsOneWidget);
      expect((await screens.cards()).length, 1);
      await screens.close();
    },
  );

  for (final mode in [ThemeMode.light, ThemeMode.dark]) {
    testWidgets(
      'in the ${mode.name} theme the basic form with its senses and presets meets the tap target, label and contrast guidelines',
      (tester) async {
        final screens = await DeckScreens.open(tester, themeMode: mode);
        await screens.push((deck) => CardEditorScreen(deck: deck));
        await tap(screens, find.text('Add meaning'));
        await tester.tap(_labelField());
        await tester.pumpAndSettle();
        expect(find.byType(LabelPresetStrip), findsOneWidget);
        final handle = tester.ensureSemantics();
        await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
        await expectLater(tester, meetsGuideline(iOSTapTargetGuideline));
        await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
        await expectLater(tester, meetsGuideline(textContrastGuideline));
        handle.dispose();
        await screens.close();
      },
    );
  }
}
