import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:flutter/material.dart' hide Card;
import 'package:flutter_test/flutter_test.dart';
import 'package:smartman/deck/deck.dart';
import 'package:smartman/deck/src/block_list.dart';
import 'package:smartman/deck/src/card_preview.dart';
import 'package:smartman/design/app_text_field.dart';

import '../home/deck_screens.dart';
import 'editor.dart';

/// The stored card.
Future<Card> _stored(DeckScreens screens) async =>
    (await screens.cards()).single;

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  Future<DeckScreens> openNew(WidgetTester tester) async {
    final screens = await DeckScreens.open(tester);
    await screens.push((deck) => CardEditorScreen(deck: deck));
    return screens;
  }

  testWidgets(
    'a new card opens with one empty Text block on each side and an add button under each, and no kind switch',
    (tester) async {
      await openNew(tester);
      expect(find.text('Add to front'), findsOneWidget);
      expect(find.text('Add to back'), findsOneWidget);
      expect(find.byType(SegmentedButton), findsNothing);
      for (final kind in ['Front & back', 'Cloze', 'Free']) {
        expect(find.text(kind), findsNothing, reason: kind);
      }
      for (final side in CardSide.values) {
        expect(
          find.descendant(of: blockList(side), matching: find.text('Text')),
          findsOneWidget,
          reason: side.name,
        );
        expect(
          find.descendant(
            of: blockList(side),
            matching: find.byType(TextField),
          ),
          findsOneWidget,
          reason: side.name,
        );
      }
    },
  );

  testWidgets(
    'the add sheet offers every block type: Text, Meanings, Table, Cloze sentence, Photo and Sound',
    (tester) async {
      final screens = await openNew(tester);
      await tapVisible(screens, find.text('Add to front'));
      final sheet = find.byType(BottomSheet);
      for (final type in [
        'Text',
        'Meanings',
        'Table',
        'Cloze sentence',
        'Photo',
        'Sound',
      ]) {
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
    },
  );

  testWidgets(
    'blocks are added, moved and deleted on each side, saved in order with template free, and reopen listed in that order',
    (tester) async {
      final screens = await openNew(tester);
      await typeBlock(tester, CardSide.front, 'apple');
      await typeBlock(tester, CardSide.back, '사과');

      await addBlock(screens, CardSide.front, 'Text');
      await typeBlock(tester, CardSide.front, 'a fruit', 1);
      await addBlock(screens, CardSide.front, 'Text');
      await typeBlock(tester, CardSide.front, 'red', 2);
      await actOnBlock(screens, CardSide.front, 3, 'Move up');

      await addBlock(screens, CardSide.back, 'Text');
      await typeBlock(tester, CardSide.back, 'gone', 1);
      await addBlock(screens, CardSide.back, 'Text');
      await typeBlock(tester, CardSide.back, 'note', 2);
      await actOnBlock(screens, CardSide.back, 2, 'Move down');
      await actOnBlock(screens, CardSide.back, 3, 'Delete');

      await tapVisible(screens, find.text('Save'));
      final card = await _stored(screens);
      expect((card.template, card.templateVersion), ('free', 1));
      expect(card.front, const [
        TextContent('apple'),
        TextContent('red'),
        TextContent('a fruit'),
      ]);
      expect(card.back, const [TextContent('사과'), TextContent('note')]);

      await screens.push((deck) => CardEditorScreen(deck: deck, card: card));
      expect(find.byType(SegmentedButton), findsNothing);
      for (final (side, texts) in [
        (CardSide.front, ['apple', 'red', 'a fruit']),
        (CardSide.back, ['사과', 'note']),
      ]) {
        expect(
          [
            for (final field in tester.widgetList<TextField>(
              find.descendant(
                of: blockList(side),
                matching: find.byType(TextField),
              ),
            ))
              field.controller!.text,
          ],
          texts,
          reason: side.name,
        );
      }
      await tapVisible(screens, find.text('Save'));
      final saved = await _stored(screens);
      expect(
        (encodeContent(saved.front), encodeContent(saved.back)),
        (encodeContent(card.front), encodeContent(card.back)),
        reason: 'saved unchanged, stored byte for byte as it was',
      );
    },
  );

  testWidgets(
    'a block menu moves up only where a block is above and down only where one is below',
    (tester) async {
      final screens = await openNew(tester);
      await addBlock(screens, CardSide.front, 'Text');
      await tapVisible(screens, find.byTooltip('Front block 1 menu'));
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
      await tapVisible(screens, find.byTooltip('Front block 2 menu'));
      expect((enabled('Move up'), enabled('Move down')), (true, false));
    },
  );

  testWidgets(
    'a card with no front block, or an empty Text block, is refused with a message, and a back may be empty once the card has a blank',
    (tester) async {
      final screens = await openNew(tester);
      await tapVisible(screens, find.text('Save'));
      expect(find.text('Enter some text'), findsNWidgets(2));
      expect(await screens.cards(), isEmpty);

      await actOnBlock(screens, CardSide.front, 1, 'Delete');
      await actOnBlock(screens, CardSide.back, 1, 'Delete');
      await tapVisible(screens, find.text('Save'));
      expect(find.text('Add at least one block'), findsNWidgets(2));
      expect(await screens.cards(), isEmpty);

      // A cloze on the front: studied on one face, so no back is needed.
      await addBlock(screens, CardSide.front, 'Cloze sentence');
      final line = blockField(CardSide.front);
      await typeInto(tester, line, 'I like tea');
      await tester.tap(line);
      await tester.pump();
      tester.widget<TextField>(line).controller!.selection =
          const TextSelection(baseOffset: 7, extentOffset: 10);
      await tester.pump();
      await screens.tap(find.text('Insert blank'));
      await tapVisible(screens, find.text('Save'));
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
    for (final side in CardSide.values) {
      await addBlock(screens, side, 'Meanings');
    }
    for (final (side, name) in [
      (CardSide.front, 'Front'),
      (CardSide.back, 'Back'),
    ]) {
      expect(
        find.descendant(
          of: blockList(side),
          matching: find.widgetWithText(AppTextField, name),
        ),
        findsOneWidget,
        reason: side.name,
      );
    }
  });

  testWidgets(
    'the preview draws a card as study does: a card with a table on its back on that one face',
    (tester) async {
      final screens = await openNew(tester);
      final preview = find.byType(CardPreview);
      expect(
        find.descendant(of: preview, matching: find.byType(WholeCardView)),
        findsNothing,
        reason: 'control: two sides of text are split',
      );
      await addBlock(screens, CardSide.back, 'Table');
      await tester.ensureVisible(preview);
      await tester.pumpAndSettle();
      expect(
        find.descendant(of: preview, matching: find.byType(WholeCardView)),
        findsOneWidget,
      );
    },
  );
}
