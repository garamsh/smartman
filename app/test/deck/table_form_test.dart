import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:flutter/material.dart' hide Card;
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smartman/deck/deck.dart';
import 'package:smartman/deck/src/card_preview.dart';
import 'package:smartman/deck/src/table_form.dart';
import 'package:smartman/design/app_text_field.dart';

import '../home/deck_screens.dart';
import 'whole_cards.dart';

/// The table form's [index]th field: the headers, then the cells row by row.
Finder _cell(int index) => find
    .descendant(of: find.byType(TableFields), matching: find.byType(TextField))
    .at(index);

/// The blanks grid's cell reading [text].
Finder _blankCell(String text) => find.descendant(
  of: find.byType(TableFields),
  matching: find.widgetWithText(InkWell, text),
);

/// The stored card, front and back.
Future<Card> _stored(DeckScreens screens) async =>
    (await screens.cards()).single;

const _capitals = TableContent(
  columns: ['Country', 'Capital'],
  rows: [
    ['France', 'Paris'],
    ['Japan', 'Tokyo'],
  ],
  blanks: [(row: 0, column: 1), (row: 1, column: 1)],
);

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  Future<DeckScreens> openTable(WidgetTester tester, {DeckScreens? on}) async {
    final screens = on ?? await DeckScreens.open(tester);
    await screens.push((deck) => CardEditorScreen(deck: deck));
    await screens.tap(find.text('Table'));
    return screens;
  }

  Future<void> enter(WidgetTester tester, Finder field, String text) async {
    await tester.ensureVisible(field);
    await tester.enterText(field, text);
    await tester.pump();
  }

  /// Taps [finder] once it is scrolled into view.
  Future<void> tap(DeckScreens screens, Finder finder) async {
    await screens.tester.ensureVisible(finder);
    await screens.tap(finder);
  }

  Future<void> save(DeckScreens screens) => tap(screens, find.text('Save'));

  /// Types the name and [_capitals]' cells into a new table, its two rows
  /// already there.
  Future<void> typeCapitals(DeckScreens screens) async {
    final tester = screens.tester;
    await enter(tester, find.widgetWithText(AppTextField, 'Front'), 'Capitals');
    final cells = [
      ..._capitals.columns,
      ..._capitals.rows.expand((row) => row),
    ];
    for (final (index, text) in cells.indexed) {
      await enter(tester, _cell(index), text);
    }
  }

  testWidgets(
    'a table saves its name, a table block of its cells and chosen blanks and the table filled as its back, and reopens in its form, unchanged when saved as it was',
    (tester) async {
      final screens = await openTable(tester);
      expect(find.text("The table's name"), findsOneWidget);
      await typeCapitals(screens);
      await tap(screens, find.text('Choose blanks'));
      expect(find.text('Tap the cells to make blanks'), findsOneWidget);
      expect(find.byType(TextField), findsOneWidget, reason: 'the name alone');
      await tap(screens, _blankCell('Paris'));
      await tap(screens, _blankCell('France'));
      await tap(screens, _blankCell('France'));
      await tap(screens, _blankCell('Tokyo'));
      expect(blanksUnder(find.byType(CardPreview)), {
        'Paris': true,
        'Tokyo': true,
      }, reason: 'the preview draws the table whole, filled');

      await save(screens);
      final card = await _stored(screens);
      expect(card.front, [const TextContent('Capitals'), _capitals]);
      // The name, then the filled table: the front's text, as photo import
      // writes a table card's back.
      expect(card.back, [TextContent('Capitals\n${_capitals.filled}')]);

      await screens.push((deck) => CardEditorScreen(deck: deck, card: card));
      expect(find.text('Basic'), findsNothing, reason: 'no switch on edit');
      expect(tester.widget<TextField>(_cell(3)).controller!.text, 'Paris');
      await save(screens);
      final saved = await _stored(screens);
      expect(saved.front, card.front, reason: 'a round trip');
      expect(saved.back, card.back);
      await screens.close();
    },
  );

  testWidgets(
    'rows and columns are added and deleted by their buttons, a blank moving with its cell, and a table keeps one row and one column',
    (tester) async {
      final screens = await openTable(tester);
      await typeCapitals(screens);
      await tap(screens, find.text('Add row'));
      await tap(screens, find.text('Add column'));
      // The headers, then three rows of three cells.
      expect(_cell(3 + 3 * 3 - 1), findsOneWidget);
      await enter(tester, _cell(2), 'Continent');
      await enter(tester, _cell(5), 'Europe');
      await enter(tester, _cell(9), 'Egypt');
      await enter(tester, _cell(10), 'Cairo');
      await tap(screens, find.text('Choose blanks'));
      await tap(screens, _blankCell('Tokyo'));
      await tap(screens, _blankCell('Cairo'));
      await tap(screens, find.text('Type cells'));

      await tap(screens, find.byTooltip('Delete row 1'));
      await tap(screens, find.byTooltip('Delete column 1'));
      await save(screens);
      expect(
        (await _stored(screens)).front.last,
        const TableContent(
          columns: ['Capital', 'Continent'],
          rows: [
            ['Tokyo', ''],
            ['Cairo', ''],
          ],
          blanks: [(row: 0, column: 0), (row: 1, column: 0)],
        ),
      );

      await screens.push((deck) => CardEditorScreen(deck: deck));
      IconButton button(String tooltip) => tester.widget<IconButton>(
        find.ancestor(
          of: find.byTooltip(tooltip),
          matching: find.byType(IconButton),
        ),
      );
      await tap(screens, find.byTooltip('Delete row 2'));
      await tap(screens, find.byTooltip('Delete column 2'));
      expect(button('Delete row 1').onPressed, isNull, reason: 'one row');
      expect(button('Delete column 1').onPressed, isNull, reason: 'one column');
      await tap(screens, find.text('Add row'));
      expect(
        button('Delete row 1').onPressed,
        isNotNull,
        reason: 'control: with two rows, either can go',
      );
      await screens.close();
    },
  );

  testWidgets(
    'a table with no blank, or with a blank on an empty cell, is refused with a message under it, and saves once both are fixed',
    (tester) async {
      final screens = await openTable(tester);
      await typeCapitals(screens);
      await save(screens);
      expect(find.text('Choose at least one cell as a blank'), findsOneWidget);
      expect(find.byType(SnackBar), findsNothing);
      expect(await screens.cards(), isEmpty);

      await tap(screens, find.text('Choose blanks'));
      await tap(screens, _blankCell('Paris'));
      await tap(screens, find.text('Type cells'));
      await enter(tester, _cell(3), '  ');
      await save(screens);
      expect(find.text('Fill in each cell chosen as a blank'), findsOneWidget);
      expect(find.text('Choose at least one cell as a blank'), findsNothing);
      expect(await screens.cards(), isEmpty);

      await enter(tester, _cell(3), 'Paris');
      await save(screens);
      expect(
        (await _stored(screens)).front.last,
        const TableContent(
          columns: ['Country', 'Capital'],
          rows: [
            ['France', 'Paris'],
            ['Japan', 'Tokyo'],
          ],
          blanks: [(row: 0, column: 1)],
        ),
        reason: 'control: fixed, it saves',
      );
      await screens.close();
    },
  );

  testWidgets(
    'a screen reader reads each cell with its place and whether it is a blank, and its action makes it a blank or a plain cell again',
    (tester) async {
      final screens = await openTable(tester);
      await typeCapitals(screens);
      final handle = tester.ensureSemantics();
      expect(find.bySemanticsLabel('Row 1, column 2'), findsOneWidget);
      expect(find.bySemanticsLabel('Column 1 heading'), findsOneWidget);
      await tap(screens, find.text('Choose blanks'));

      /// Performs the custom action named [label] on the cell read as [cell].
      Future<void> act(String cell, String label) async {
        final node = tester.getSemantics(find.bySemanticsLabel(cell));
        final actions = node.getSemanticsData().customSemanticsActionIds!;
        final id = actions.singleWhere(
          (id) => CustomSemanticsAction.getAction(id)!.label == label,
        );
        node.owner!.performAction(node.id, SemanticsAction.customAction, id);
        await tester.pump();
      }

      await act('Paris, Row 1, column 2', 'Make blank');
      expect(find.bySemanticsLabel('Paris, Row 1, column 2, blank'), findsOne);
      await act('Paris, Row 1, column 2, blank', 'Remove blank');
      await act('Tokyo, Row 2, column 2', 'Make blank');
      handle.dispose();

      await save(screens);
      expect(
        (await _stored(screens)).front.last,
        const TableContent(
          columns: ['Country', 'Capital'],
          rows: [
            ['France', 'Paris'],
            ['Japan', 'Tokyo'],
          ],
          blanks: [(row: 1, column: 1)],
        ),
      );
      await screens.close();
    },
  );

  testWidgets(
    'a stored table card opens in the table form, its name in the front, and still deletes',
    (tester) async {
      final screens = await DeckScreens.open(tester);
      await tester.runAsync(
        () => screens.repository.addCard(
          screens.deck.id,
          front: [const TextContent('Capitals'), _capitals],
          back: [TextContent(_capitals.filled)],
        ),
      );
      final card = await _stored(screens);
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
        'Capitals',
      );
      expect(blanksUnder(find.byType(CardPreview)), {
        'Paris': true,
        'Tokyo': true,
      });
      await screens.tap(find.byTooltip('Delete card'));
      await screens.tap(find.text('Delete'));
      expect(await screens.cards(), isEmpty);
      await screens.close();
    },
  );

  testWidgets(
    'a table card as photo import writes it, its back the name and the filled table, is stored as it was when saved unchanged',
    (tester) async {
      final screens = await DeckScreens.open(tester);
      const front = [TextContent('Capitals'), _capitals];
      final back = [TextContent(plainText(front))];
      // The setup is photo import's shape: the name line, then the table.
      expect(back.single.text, startsWith('Capitals\n'));
      await tester.runAsync(
        () => screens.repository.addCards(AddToDeck(screens.deck.id), [
          IncomingCard(
            front: front,
            back: back,
            onDuplicate: DuplicateChoice.mergeBack,
          ),
        ]),
      );
      final card = await _stored(screens);
      await screens.push((deck) => CardEditorScreen(deck: deck, card: card));
      await save(screens);
      final saved = await _stored(screens);
      expect(saved.front, front);
      expect(saved.back, back);
      await screens.close();
    },
  );

  testWidgets(
    'a table whose name and cells are already a card opens the duplicate sheet',
    (tester) async {
      final screens = await DeckScreens.open(tester);
      await tester.runAsync(
        () => screens.repository.addCard(
          screens.deck.id,
          front: [const TextContent('Capitals'), _capitals],
          back: [TextContent(_capitals.filled)],
        ),
      );
      await openTable(tester, on: screens);
      await typeCapitals(screens);
      await tap(screens, find.text('Choose blanks'));
      await tap(screens, _blankCell('France'));
      await save(screens);
      expect(find.text('Add anyway'), findsOneWidget);
      expect((await screens.cards()).length, 1);
      await screens.close();
    },
  );

  for (final mode in [ThemeMode.light, ThemeMode.dark]) {
    testWidgets(
      'in the ${mode.name} theme the table form meets the tap target, label and contrast guidelines in both of its modes',
      (tester) async {
        final screens = await DeckScreens.open(tester, themeMode: mode);
        await openTable(tester, on: screens);
        await typeCapitals(screens);
        final handle = tester.ensureSemantics();
        Future<void> meetsGuidelines() async {
          await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
          await expectLater(tester, meetsGuideline(iOSTapTargetGuideline));
          await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
          await expectLater(tester, meetsGuideline(textContrastGuideline));
        }

        await meetsGuidelines();
        await tap(screens, find.text('Choose blanks'));
        await tap(screens, _blankCell('Paris'));
        await enter(tester, find.widgetWithText(AppTextField, 'Front'), '');
        await save(screens);
        expect(find.text('Enter some text'), findsOneWidget);
        await meetsGuidelines();
        handle.dispose();
        await screens.close();
      },
    );
  }
}
