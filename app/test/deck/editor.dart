import 'package:flutter/material.dart' hide Card;
import 'package:flutter_test/flutter_test.dart';
import 'package:smartman/deck/src/block_list.dart';

import '../home/deck_screens.dart';

/// The block list of [side]: the first on screen is the front's.
Finder blockList(CardSide side) => find.byType(BlockList).at(side.index);

/// The [index]th text field of [side]'s block list.
Finder blockField(CardSide side, [int index = 0]) => find
    .descendant(of: blockList(side), matching: find.byType(TextField))
    .at(index);

/// The text field labelled or hinted [label] inside [side]'s block list,
/// found by its decoration, so it is found once it holds text too.
Finder labelledField(CardSide side, String label) => find.descendant(
  of: blockList(side),
  matching: find.byWidgetPredicate(
    (widget) =>
        widget is TextField &&
        (widget.decoration?.labelText == label ||
            widget.decoration?.hintText == label),
  ),
);

/// The "+ 추가" row at the end of [side]'s group, found by what a screen
/// reader reads for it.
Finder addRow(CardSide side) => find.bySemanticsLabel(
  side == CardSide.front ? 'Add to front' : 'Add to back',
);

/// Brings [finder] into view and taps it.
Future<void> tapVisible(DeckScreens screens, Finder finder) async {
  await screens.tester.ensureVisible(finder);
  await screens.tester.pumpAndSettle();
  await screens.tap(finder);
}

/// Types [text] into [field], brought into view first.
Future<void> typeInto(WidgetTester tester, Finder field, String text) async {
  await tester.ensureVisible(field);
  await tester.enterText(field, text);
  await tester.pump();
}

/// Types [text] into the [index]th text field of [side]'s blocks.
Future<void> typeBlock(
  WidgetTester tester,
  CardSide side,
  String text, [
  int index = 0,
]) => typeInto(tester, blockField(side, index), text);

/// Adds a block of [type] to [side] through its button and sheet.
Future<void> addBlock(DeckScreens screens, CardSide side, String type) async {
  await tapVisible(screens, addRow(side));
  await screens.tap(find.text(type).last);
}

/// Chooses [action] in the menu of [side]'s [number]th block.
Future<void> actOnBlock(
  DeckScreens screens,
  CardSide side,
  int number,
  String action,
) async {
  final name = side == CardSide.front ? 'Front' : 'Back';
  await tapVisible(screens, find.byTooltip('$name block $number menu'));
  await screens.tap(find.text(action).last);
}

/// Replaces [side]'s blocks with one new block of [type]: the side's first
/// block, a new card's empty Text, is deleted, and [type] added in its place.
Future<void> replaceFirstBlock(
  DeckScreens screens,
  CardSide side,
  String type,
) async {
  await actOnBlock(screens, side, 1, 'Delete');
  await addBlock(screens, side, type);
}
