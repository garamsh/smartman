import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:flutter/material.dart' hide Card;
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:smartman/deck/deck.dart';
import 'package:smartman/deck/src/block_list.dart';
import 'package:smartman/deck/src/card_preview_screen.dart';

import '../home/deck_screens.dart';
import '../word_breaks.dart';
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
    'a new card opens with one empty Text block on each side and an add row ending each side, no kind switch, and no icon but each block\'s menu',
    (tester) async {
      await openNew(tester);
      expect(find.bySemanticsLabel('Add to front'), findsOneWidget);
      expect(find.bySemanticsLabel('Add to back'), findsOneWidget);
      expect(find.byType(SegmentedButton), findsNothing);
      for (final kind in ['Front & back', 'Cloze', 'Free']) {
        expect(find.text(kind), findsNothing, reason: kind);
      }
      for (final side in CardSide.values) {
        // A Text block is named by nothing but its field.
        expect(
          find.descendant(of: blockList(side), matching: find.text('Text')),
          findsNothing,
          reason: side.name,
        );
        expect(
          [
            for (final icon in tester.widgetList<Icon>(
              find.descendant(of: blockList(side), matching: find.byType(Icon)),
            ))
              icon.icon,
          ],
          [LucideIcons.ellipsis],
          reason: '${side.name}: the block menu alone',
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
      await tapVisible(screens, find.bySemanticsLabel('Add to front'));
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
      expect(
        find.descendant(of: sheet, matching: find.byType(Icon)),
        findsNothing,
        reason: 'no icon beside a type',
      );
      expect(
        find.descendant(of: sheet, matching: shownText('Choose cells to hide')),
        findsOneWidget,
        reason: 'control: a type that needs one has its line',
      );
      expect(
        find.descendant(
          of: sheet,
          matching: shownText('A word, a sentence or a note'),
        ),
        findsNothing,
        reason: 'Text says enough by its name',
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
      expect(find.text('Write something'), findsNWidgets(2));
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

  testWidgets(
    'a new cloze card saves with its back\'s untouched Text block, which is not stored, while a split card\'s empty back is still refused',
    (tester) async {
      final screens = await openNew(tester);
      // Control: with no blank, the card is split and its empty back refused.
      await typeBlock(tester, CardSide.front, 'Chat');
      await tapVisible(screens, find.text('Save'));
      expect(find.text('Write something'), findsOneWidget);
      expect(await screens.cards(), isEmpty);

      await replaceFirstBlock(screens, CardSide.front, 'Cloze sentence');
      final line = blockField(CardSide.front);
      await typeInto(tester, line, 'I like tea');
      await tester.tap(line);
      await tester.pump();
      tester.widget<TextField>(line).controller!.selection =
          const TextSelection(baseOffset: 7, extentOffset: 10);
      await tester.pump();
      await screens.tap(find.text('Insert blank'));
      // The back still holds the new card's empty Text block.
      expect(
        find.descendant(
          of: blockList(CardSide.back),
          matching: find.byType(TextField),
        ),
        findsOneWidget,
      );
      expect(
        tester.widget<TextField>(blockField(CardSide.back)).controller!.text,
        '',
      );

      await tapVisible(screens, find.text('Save'));
      expect(find.text('Write something'), findsNothing);
      final card = await _stored(screens);
      expect(card.front, const [
        ClozeContent('I like ___', ['tea']),
      ]);
      expect(card.back, isEmpty);
      await screens.close();
    },
  );

  testWidgets(
    'no field inside a side is named by that side, which its label above names: a one-meaning Meanings block\'s field is hinted Meaning',
    (tester) async {
      final screens = await openNew(tester);
      for (final side in CardSide.values) {
        await addBlock(screens, side, 'Meanings');
      }
      for (final (side, name) in [
        (CardSide.front, 'Front'),
        (CardSide.back, 'Back'),
      ]) {
        // Control: the side is named once, by its label over the group.
        expect(find.text(name), findsOneWidget, reason: side.name);
        expect(
          find.descendant(of: blockList(side), matching: find.text(name)),
          findsNothing,
          reason: '${side.name}: its name is not repeated inside it',
        );
        expect(labelledField(side, name), findsNothing, reason: side.name);
        expect(
          labelledField(side, 'Meaning'),
          findsOneWidget,
          reason: side.name,
        );
      }
    },
  );

  testWidgets(
    'the preview draws a card as study does: a card with a table on its back on that one face',
    (tester) async {
      final screens = await openNew(tester);
      final preview = find.byType(CardPreviewScreen);
      await screens.tap(find.text('Preview'));
      expect(
        find.descendant(of: preview, matching: find.byType(WholeCardView)),
        findsNothing,
        reason: 'control: two sides of text are front then back',
      );
      await screens.tap(find.byTooltip('Close'));
      await addBlock(screens, CardSide.back, 'Table');
      await screens.tap(find.text('Preview'));
      expect(
        find.descendant(of: preview, matching: find.byType(WholeCardView)),
        findsOneWidget,
      );
    },
  );
}
