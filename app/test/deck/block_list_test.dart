import 'dart:convert';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:flutter/material.dart' hide Card;
import 'package:flutter_test/flutter_test.dart';
import 'package:smartman/deck/deck.dart';
import 'package:smartman/deck/src/block_list.dart';
import 'package:smartman/deck/src/card_kind.dart';
import 'package:smartman/deck/src/card_preview.dart';
import 'package:smartman/design/app_text_field.dart';

import '../home/deck_screens.dart';

/// [blocks] as stored, without the ids a write gives them.
List<Object?> _withoutIds(List<Content> blocks) => [
  for (final block in jsonDecode(encodeContent(blocks)) as List<Object?>)
    {...block! as Map<String, Object?>}..remove('id'),
];

/// The stored card.
Future<Card> _stored(DeckScreens screens) async =>
    (await screens.cards()).single;

/// The block list of [side]: the first on screen is the front's.
Finder _list(CardSide side) => find.byType(BlockList).at(side.index);

/// The [index]th text field of [side]'s block list.
Finder _blockField(CardSide side, [int index = 0]) => find
    .descendant(of: _list(side), matching: find.byType(TextField))
    .at(index);

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  Future<DeckScreens> openNew(WidgetTester tester) async {
    final screens = await DeckScreens.open(tester);
    await screens.push((deck) => CardEditorScreen(deck: deck));
    return screens;
  }

  Future<void> tap(DeckScreens screens, Finder finder) async {
    await screens.tester.ensureVisible(finder);
    await screens.tester.pumpAndSettle();
    await screens.tap(finder);
  }

  Future<void> type(WidgetTester tester, Finder field, String text) async {
    await tester.ensureVisible(field);
    await tester.enterText(field, text);
    await tester.pump();
  }

  /// Adds a block of [type] to [side] through its button and sheet.
  Future<void> add(DeckScreens screens, CardSide side, String type) async {
    await tap(
      screens,
      find.text(side == CardSide.front ? 'Add to front' : 'Add to back'),
    );
    await screens.tap(find.text(type).last);
  }

  /// Chooses [action] in the menu of [side]'s [number]th block.
  Future<void> act(
    DeckScreens screens,
    CardSide side,
    int number,
    String action,
  ) async {
    final name = side == CardSide.front ? 'Front' : 'Back';
    await tap(screens, find.byTooltip('$name block $number menu'));
    await screens.tap(find.text(action).last);
  }

  testWidgets(
    'Free opens with one empty Text block on each side, and Front & back opens as before with an add button under each side',
    (tester) async {
      final screens = await openNew(tester);
      expect(find.text('Add to front'), findsOneWidget);
      expect(find.text('Add to back'), findsOneWidget);
      expect(find.widgetWithText(AppTextField, 'Front'), findsOneWidget);
      expect(find.byTooltip('Front block 1 menu'), findsNothing);

      await screens.tap(find.text('Free'));
      expect(find.widgetWithText(AppTextField, 'Front'), findsNothing);
      for (final side in CardSide.values) {
        expect(
          find.descendant(of: _list(side), matching: find.text('Text')),
          findsOneWidget,
          reason: side.name,
        );
        expect(
          find.descendant(of: _list(side), matching: find.byType(TextField)),
          findsOneWidget,
          reason: side.name,
        );
      }
    },
  );

  testWidgets(
    'the add sheet offers Text, Meanings, Table and Cloze sentence, and no photo or recording',
    (tester) async {
      final screens = await openNew(tester);
      await tap(screens, find.text('Add to front'));
      final sheet = find.byType(BottomSheet);
      for (final type in ['Text', 'Meanings', 'Table', 'Cloze sentence']) {
        expect(
          find.descendant(of: sheet, matching: find.text(type)),
          findsOneWidget,
          reason: type,
        );
      }
      expect(
        find.descendant(of: sheet, matching: find.byType(ListTile)),
        findsNothing,
      );
      for (final type in ['Photo', 'Audio', 'Recording']) {
        expect(find.text(type), findsNothing, reason: type);
      }
    },
  );

  testWidgets(
    'on Front & back, blocks are added, moved and deleted on each side, saved after the form\'s, and the card keeps its template and reopens with them listed',
    (tester) async {
      final screens = await openNew(tester);
      await type(tester, find.widgetWithText(AppTextField, 'Front'), 'apple');
      await type(tester, find.widgetWithText(AppTextField, 'Back'), '사과');

      await add(screens, CardSide.front, 'Text');
      await type(tester, _blockField(CardSide.front), 'a fruit');
      await add(screens, CardSide.front, 'Text');
      await type(tester, _blockField(CardSide.front, 1), 'red');
      await act(screens, CardSide.front, 2, 'Move up');

      await add(screens, CardSide.back, 'Text');
      await type(tester, _blockField(CardSide.back), 'gone');
      await add(screens, CardSide.back, 'Text');
      await type(tester, _blockField(CardSide.back, 1), 'note');
      await act(screens, CardSide.back, 1, 'Move down');
      await act(screens, CardSide.back, 2, 'Delete');

      await tap(screens, find.text('Save'));
      final card = await _stored(screens);
      expect(card.template, 'flip');
      expect(card.front, const [
        TextContent('apple'),
        TextContent('red'),
        TextContent('a fruit'),
      ]);
      expect(card.back, const [TextContent('사과'), TextContent('note')]);

      await screens.push((deck) => CardEditorScreen(deck: deck, card: card));
      expect(
        tester
            .widget<TextField>(
              find.descendant(
                of: find.widgetWithText(AppTextField, 'Front'),
                matching: find.byType(TextField),
              ),
            )
            .controller!
            .text,
        'apple',
        reason: 'the form edits its own block alone',
      );
      expect(find.byTooltip('Front block 2 menu'), findsOneWidget);
      expect(find.byTooltip('Back block 1 menu'), findsOneWidget);
      await tap(screens, find.text('Save'));
      expect(
        _withoutIds((await _stored(screens)).back),
        _withoutIds(card.back),
        reason: 'saved unchanged, stored as it was',
      );
    },
  );

  testWidgets(
    'a block menu moves up only where a block is above and down only where one is below',
    (tester) async {
      final screens = await openNew(tester);
      await screens.tap(find.text('Free'));
      await add(screens, CardSide.front, 'Text');
      await tap(screens, find.byTooltip('Front block 1 menu'));
      bool enabled(String item) => switch (tester.widget(
        find
            .ancestor(
              of: find.text(item).last,
              matching: find.byWidgetPredicate(
                (widget) => widget is PopupMenuItem,
              ),
            )
            .first,
      )) {
        PopupMenuItem(:final enabled) => enabled,
        _ => fail('$item is not a menu item'),
      };
      expect((enabled('Move up'), enabled('Move down')), (false, true));
      await tester.tapAt(Offset.zero);
      await tester.pumpAndSettle();
      await tap(screens, find.byTooltip('Front block 2 menu'));
      expect((enabled('Move up'), enabled('Move down')), (true, false));
    },
  );

  testWidgets(
    'a Free card saves template free with its blocks in order, and reopens with each side listed',
    (tester) async {
      final screens = await openNew(tester);
      await screens.tap(find.text('Free'));
      await type(tester, _blockField(CardSide.front), 'apple');
      await add(screens, CardSide.back, 'Meanings');
      await type(
        tester,
        find.descendant(
          of: _list(CardSide.back),
          matching: find.widgetWithText(AppTextField, 'Back'),
        ),
        '사과',
      );
      await type(tester, _blockField(CardSide.back), 'red');
      await act(screens, CardSide.back, 1, 'Move down');

      await tap(screens, find.text('Save'));
      final card = await _stored(screens);
      expect(card.template, 'free');
      expect(card.front, const [TextContent('apple')]);
      expect(card.back, const [
        SensesContent([CardSense(meaning: '사과')]),
        TextContent('red'),
      ]);

      await screens.push((deck) => CardEditorScreen(deck: deck, card: card));
      expect(find.byType(SegmentedButton<CardKind>), findsNothing);
      expect(find.widgetWithText(AppTextField, 'Front'), findsNothing);
      expect(
        find.descendant(
          of: _list(CardSide.back),
          matching: find.text('Meanings'),
        ),
        findsOneWidget,
      );
      await type(tester, _blockField(CardSide.front), 'green apple');
      await tap(screens, find.text('Save'));
      final saved = await _stored(screens);
      expect(saved.template, 'free');
      expect(saved.front, const [TextContent('green apple')]);
      expect(_withoutIds(saved.back), _withoutIds(card.back));
    },
  );

  testWidgets(
    'a Free card with no front block, or an empty Text block, is refused with a message, and a back may be empty once the card has a blank',
    (tester) async {
      final screens = await openNew(tester);
      await screens.tap(find.text('Free'));
      await tap(screens, find.text('Save'));
      expect(find.text('Enter some text'), findsNWidgets(2));
      expect(await screens.cards(), isEmpty);

      await act(screens, CardSide.front, 1, 'Delete');
      await act(screens, CardSide.back, 1, 'Delete');
      await tap(screens, find.text('Save'));
      expect(find.text('Add at least one block'), findsNWidgets(2));
      expect(await screens.cards(), isEmpty);

      // A cloze on the front: studied on one face, so no back is needed.
      await add(screens, CardSide.front, 'Cloze sentence');
      final line = _blockField(CardSide.front);
      await type(tester, line, 'I like tea');
      await tester.tap(line);
      await tester.pump();
      tester.widget<TextField>(line).controller!.selection =
          const TextSelection(baseOffset: 7, extentOffset: 10);
      await tester.pump();
      await screens.tap(find.text('Insert blank'));
      await tap(screens, find.text('Save'));
      final card = await _stored(screens);
      expect(card.front, const [
        ClozeContent('I like ___', ['tea']),
      ]);
      expect(card.back, isEmpty);
      expect(card.template, 'free');
    },
  );

  testWidgets('a one-meaning Meanings block names its field by its side', (
    tester,
  ) async {
    final screens = await openNew(tester);
    await screens.tap(find.text('Free'));
    for (final side in CardSide.values) {
      await add(screens, side, 'Meanings');
    }
    for (final (side, name) in [
      (CardSide.front, 'Front'),
      (CardSide.back, 'Back'),
    ]) {
      expect(
        find.descendant(
          of: _list(side),
          matching: find.widgetWithText(AppTextField, name),
        ),
        findsOneWidget,
        reason: side.name,
      );
    }
  });

  testWidgets(
    'the preview draws a card as study does: a Free card with a table on its back on that one face',
    (tester) async {
      final screens = await openNew(tester);
      await screens.tap(find.text('Free'));
      final preview = find.byType(CardPreview);
      expect(
        find.descendant(of: preview, matching: find.byType(WholeCardView)),
        findsNothing,
        reason: 'control: two sides of text are split',
      );
      await add(screens, CardSide.back, 'Table');
      await tester.ensureVisible(preview);
      await tester.pumpAndSettle();
      expect(
        find.descendant(of: preview, matching: find.byType(WholeCardView)),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'a new card saved in Free starts the deck\'s next new card in Free',
    (tester) async {
      final screens = await openNew(tester);
      await screens.tap(find.text('Free'));
      await type(tester, _blockField(CardSide.front), 'apple');
      await type(tester, _blockField(CardSide.back), '사과');
      await tap(screens, find.text('Save'));
      expect((await _stored(screens)).template, 'free');

      await screens.push((deck) => CardEditorScreen(deck: deck));
      expect(
        tester
            .widget<SegmentedButton<CardKind>>(
              find.byType(SegmentedButton<CardKind>),
            )
            .selected,
        {CardKind.free},
      );
    },
  );
}
