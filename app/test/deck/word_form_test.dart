import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:flutter/material.dart' hide Card;
import 'package:flutter_test/flutter_test.dart';
import 'package:smartman/deck/deck.dart';
import 'package:smartman/design/app_text_field.dart';

import '../home/deck_screens.dart';

/// The field labelled [label], the [index]th of those on screen.
Finder _field(String label, [int index = 0]) =>
    find.widgetWithText(AppTextField, label).at(index);

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

  /// Types [text] into the [index]th field labelled [label].
  Future<void> enter(
    WidgetTester tester,
    String label,
    String text, [
    int index = 0,
  ]) async {
    await tester.ensureVisible(_field(label, index));
    await tester.enterText(_field(label, index), text);
    await tester.pump();
  }

  /// Taps [finder] once it is scrolled into view.
  Future<void> tap(DeckScreens screens, Finder finder) async {
    await screens.tester.ensureVisible(finder);
    await screens.tap(finder);
  }

  Future<void> addLabel(
    DeckScreens screens,
    String choice, [
    int index = 0,
  ]) async {
    await tap(screens, find.text('Add label').at(index));
    await screens.tap(find.text(choice));
  }

  testWidgets(
    'a new card starts basic, the switch makes it a word, and the deck starts its next new card in that kind',
    (tester) async {
      final screens = await openNew(tester);
      expect(find.text('Meaning 1'), findsNothing);
      expect(find.widgetWithText(AppTextField, 'Back'), findsOneWidget);

      await screens.tap(find.text('Word'));
      expect(find.text('Meaning 1'), findsOneWidget);
      expect(find.widgetWithText(AppTextField, 'Back'), findsNothing);

      await screens.tap(find.byTooltip('Close'));
      await screens.push((deck) => CardEditorScreen(deck: deck));
      expect(find.text('Meaning 1'), findsOneWidget, reason: 'remembered');

      await screens.tap(find.text('Basic'));
      await screens.tap(find.byTooltip('Close'));
      await screens.push((deck) => CardEditorScreen(deck: deck));
      expect(
        find.widgetWithText(AppTextField, 'Back'),
        findsOneWidget,
        reason: 'control: the switch back to basic is remembered too',
      );
      await screens.close();
    },
  );

  testWidgets(
    'a word saves its headword and one senses block of its labels, meanings and examples one per line, and reopens in its form, unchanged when saved as it was',
    (tester) async {
      final screens = await openNew(tester);
      await screens.tap(find.text('Word'));
      await enter(tester, 'Front', 'apple');
      await addLabel(screens, '[명] noun');
      await enter(tester, 'Meaning', '사과');
      await enter(tester, 'Examples', ' an apple \n\n Apple pie');
      await tap(screens, find.text('Add meaning'));
      await tap(screens, find.text('Add label').at(1));
      await enter(tester, 'Other label', 'object');
      await tap(screens, find.text('Add this label'));
      await enter(tester, 'Meaning', '능금', 1);
      expect(find.text('[명]'), findsWidgets, reason: 'the label as a chip');

      await tap(screens, find.text('Save'));
      const senses = SensesContent([
        CardSense(
          labels: [_noun],
          meaning: '사과',
          examples: ['an apple', 'Apple pie'],
        ),
        CardSense(labels: [OtherLabel('object')], meaning: '능금'),
      ]);
      final card = await _stored(screens);
      expect(card.front, [const TextContent('apple')]);
      expect(card.back, [senses]);

      await screens.push((deck) => CardEditorScreen(deck: deck, card: card));
      expect(find.text('Basic'), findsNothing, reason: 'no switch on edit');
      expect(find.text('Meaning 2'), findsOneWidget);
      await tap(screens, find.text('Save'));
      expect((await _stored(screens)).back, [senses], reason: 'a round trip');
      await screens.close();
    },
  );

  testWidgets(
    'editing a word changes its senses and keeps any other block of its back, such as its extras',
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
      await enter(tester, 'Meaning', '얼굴, 표면');
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
    'a sense without a meaning and an empty headword are refused, each with a message on its field',
    (tester) async {
      final screens = await openNew(tester);
      await screens.tap(find.text('Word'));
      await tap(screens, find.text('Add meaning'));
      await enter(tester, 'Meaning', '사과');
      await tap(screens, find.text('Save'));
      expect(find.text('Enter the meaning'), findsOneWidget);
      expect(find.text('Enter some text'), findsOneWidget);
      expect(await screens.cards(), isEmpty);

      // The headword alone filled: the form refuses the empty meaning itself,
      // without a save that fails.
      await enter(tester, 'Front', 'apple');
      await tap(screens, find.text('Save'));
      expect(find.text('Enter the meaning'), findsOneWidget);
      expect(find.text('Enter some text'), findsNothing);
      expect(find.byType(SnackBar), findsNothing);
      expect(await screens.cards(), isEmpty);

      await enter(tester, 'Meaning', '능금', 1);
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
    'senses move by their buttons and are deleted by theirs, a label by its own, and a word keeps one sense',
    (tester) async {
      final screens = await openNew(tester);
      await screens.tap(find.text('Word'));
      await enter(tester, 'Front', 'apple');
      await enter(tester, 'Meaning', 'first');
      await tap(screens, find.text('Add meaning'));
      await enter(tester, 'Meaning', 'second', 1);
      await tap(screens, find.text('Add meaning'));
      await enter(tester, 'Meaning', 'third', 2);
      await addLabel(screens, '[명] noun', 2);

      // [first, second, third [명]] becomes [first, third [명], second], then
      // [third [명], first, second]; the label goes, and then the third sense.
      await tap(screens, find.byTooltip('Move meaning 3 up'));
      await tap(screens, find.byTooltip('Move meaning 1 down'));
      await tap(screens, find.byTooltip('Remove label [명]'));
      await tap(screens, find.byTooltip('Delete meaning 3'));
      await tap(screens, find.text('Save'));
      expect((await _stored(screens)).back, [
        const SensesContent([
          CardSense(meaning: 'third'),
          CardSense(meaning: 'first'),
        ]),
      ]);

      // Save closed the editor; a new card starts with one sense.
      await screens.push((deck) => CardEditorScreen(deck: deck));
      IconButton button(String tooltip) => tester.widget<IconButton>(
        find.ancestor(
          of: find.byTooltip(tooltip),
          matching: find.byType(IconButton),
        ),
      );
      expect(button('Delete meaning 1').onPressed, isNull, reason: 'one sense');
      expect(button('Move meaning 1 up').onPressed, isNull);
      expect(button('Move meaning 1 down').onPressed, isNull);
      await tap(screens, find.text('Add meaning'));
      expect(
        button('Delete meaning 1').onPressed,
        isNotNull,
        reason: 'control: with two, either can go',
      );
      await screens.close();
    },
  );

  testWidgets(
    'a duplicate headword opens the duplicate sheet, as a basic card does',
    (tester) async {
      final screens = await DeckScreens.open(tester, cards: {'apple': '사과'});
      await screens.push((deck) => CardEditorScreen(deck: deck));
      await screens.tap(find.text('Word'));
      await enter(tester, 'Front', ' Apple ');
      await enter(tester, 'Meaning', '능금');
      await tap(screens, find.text('Save'));
      expect(find.text('Add anyway'), findsOneWidget);
      expect((await screens.cards()).length, 1);
      await screens.close();
    },
  );

  for (final mode in [ThemeMode.light, ThemeMode.dark]) {
    testWidgets(
      'in the ${mode.name} theme the word form meets the tap target, label and contrast guidelines',
      (tester) async {
        final screens = await DeckScreens.open(tester, themeMode: mode);
        await screens.push((deck) => CardEditorScreen(deck: deck));
        await screens.tap(find.text('Word'));
        await addLabel(screens, '[명] noun');
        await tap(screens, find.text('Add meaning'));
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
