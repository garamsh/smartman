import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:flutter/material.dart' hide Card;
import 'package:flutter_test/flutter_test.dart';
import 'package:smartman/deck/deck.dart';
import 'package:smartman/deck/src/card_preview.dart';
import 'package:smartman/design/app_button.dart';
import 'package:smartman/design/app_text_field.dart';

import '../home/deck_screens.dart';
import 'whole_cards.dart';

/// The text of the preview's two halves, front then back.
List<String?> _preview(WidgetTester tester) => [
  for (final text in tester.widgetList<Text>(
    find.descendant(
      of: find.byType(CardPreview).first,
      matching: find.byType(Text),
    ),
  ))
    text.data ?? text.textSpan?.toPlainText(),
];

/// The text of every stored card, front and back.
Future<List<(String, String)>> _stored(DeckScreens screens) async => [
  for (final card in await screens.cards())
    (plainText(card.front), plainText(card.back)),
];

bool _focused(WidgetTester tester, String label) => tester
    .widget<EditableText>(
      find.descendant(
        of: find.widgetWithText(AppTextField, label),
        matching: find.byType(EditableText),
      ),
    )
    .focusNode
    .hasFocus;

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  Future<DeckScreens> openNew(
    WidgetTester tester, {
    Map<String, String> cards = const {},
  }) async {
    final screens = await DeckScreens.open(tester, cards: cards);
    await screens.push((deck) => CardEditorScreen(deck: deck));
    return screens;
  }

  testWidgets(
    'the preview shows the card as it is typed, front left and back right',
    (tester) async {
      final screens = await openNew(tester);
      expect(find.text('Add card'), findsOneWidget);
      expect(find.text('French'), findsOneWidget);
      expect(_preview(tester), ['', '']);

      await screens.enter('Front', 'Chat');
      expect(_preview(tester), ['Chat', '']);

      await screens.enter('Back', 'cat');
      expect(_preview(tester), ['Chat', 'cat']);
      await screens.close();
    },
  );

  testWidgets('Save stores the card and closes the editor', (tester) async {
    final screens = await openNew(tester);

    await screens.enter('Front', 'Chat');
    await screens.enter('Back', 'cat');
    await screens.tap(find.text('Save'));

    expect(find.byType(CardEditorScreen), findsNothing);
    expect(await _stored(screens), [('Chat', 'cat')]);
    await screens.close();
  });

  testWidgets(
    'Save and next card stores the card and leaves the editor open and empty, focused on the front',
    (tester) async {
      final screens = await openNew(tester);
      await screens.enter('Front', 'Chat');
      await screens.enter('Back', 'cat');
      await tester.showKeyboard(find.widgetWithText(TextField, 'cat'));
      // Control: focus has left the front before the save.
      expect(_focused(tester, 'Front'), isFalse);

      await screens.tap(find.text('Save and next card'));

      expect(find.byType(CardEditorScreen), findsOneWidget);
      expect(await _stored(screens), [('Chat', 'cat')]);
      expect(find.widgetWithText(TextField, 'Chat'), findsNothing);
      expect(find.widgetWithText(TextField, 'cat'), findsNothing);
      expect(_preview(tester), ['', '']);
      expect(_focused(tester, 'Front'), isTrue);

      await screens.enter('Front', 'Chien');
      await screens.enter('Back', 'dog');
      await screens.tap(find.text('Save and next card'));
      expect(await _stored(screens), [('Chat', 'cat'), ('Chien', 'dog')]);
      await screens.close();
    },
  );

  testWidgets('an empty side is refused with a message on its field', (
    tester,
  ) async {
    final screens = await openNew(tester);
    await screens.enter('Front', 'Chat');

    await screens.tap(find.text('Save and next card'));

    expect(find.text('Enter some text'), findsOneWidget);
    expect(await _stored(screens), isEmpty);
    await screens.close();
  });

  testWidgets(
    'a table card opens read-only: previewed whole and filled, with a note and no field or Save, and still deletes, where a text card opens its fields',
    (tester) async {
      final screens = await DeckScreens.open(tester, cards: {'Chat': 'cat'});
      const table = TableContent(
        columns: ['Capital', 'Country'],
        rows: [
          ['Paris', 'France'],
        ],
        blanks: [(row: 0, column: 0)],
      );
      await tester.runAsync(
        () => screens.repository.addCard(
          screens.deck.id,
          front: [const TextContent('Capitals'), table],
          back: [TextContent(table.filled)],
        ),
      );
      final cards = await screens.cards();
      final whole = cards.firstWhere((card) => isWholeCard(card.front));

      // Control: a text card opens its fields and Save.
      await screens.push(
        (deck) => CardEditorScreen(deck: deck, card: cards.first),
      );
      expect(find.widgetWithText(AppTextField, 'Front'), findsOneWidget);
      expect(find.text('Save'), findsOneWidget);
      await screens.tap(find.byTooltip('Close'));

      await screens.push((deck) => CardEditorScreen(deck: deck, card: whole));
      expect(blanksUnder(find.byType(CardPreview)), {'Paris': true});
      expect(
        find.text(
          "Table and cloze cards can't be edited yet. You can delete one.",
        ),
        findsOneWidget,
      );
      expect(find.byType(AppTextField), findsNothing);
      expect(find.text('Save'), findsNothing);

      await screens.tap(find.byTooltip('Delete card'));
      await screens.tap(find.text('Delete'));
      expect(await _stored(screens), [('Chat', 'cat')]);
      await screens.close();
    },
  );

  testWidgets(
    'a reversed word, its senses on the front, edits as a basic card: saved as it was it keeps them, and edited its front becomes the text typed, as the note says',
    (tester) async {
      final screens = await DeckScreens.open(tester);
      const senses = SensesContent([
        CardSense(
          labels: [PartOfSpeechLabel(PartOfSpeech.noun, '명')],
          meaning: '사과',
        ),
      ]);
      await tester.runAsync(
        () => screens.repository.addCard(
          screens.deck.id,
          front: [senses],
          back: [const TextContent('apple')],
        ),
      );
      Future<Card> stored() async => (await screens.cards()).single;

      final card = await stored();
      await screens.push((deck) => CardEditorScreen(deck: deck, card: card));
      expect(
        find.text('Editing the front saves labels such as [명] as plain text.'),
        findsOneWidget,
      );
      expect(find.widgetWithText(TextField, '[명] 사과'), findsOneWidget);
      // Control: saved as it was, the front keeps its senses block.
      await screens.tap(find.text('Save'));
      expect((await stored()).front, [senses]);

      await screens.push((deck) => CardEditorScreen(deck: deck, card: card));
      await tester.enterText(
        find.widgetWithText(TextField, '[명] 사과'),
        '[명] 사과, 능금',
      );
      await tester.pumpAndSettle();
      await screens.tap(find.text('Save'));
      expect((await stored()).front, [const TextContent('[명] 사과, 능금')]);
      await screens.close();
    },
  );

  testWidgets('editing a card offers Save only, and deletes after confirming', (
    tester,
  ) async {
    final screens = await DeckScreens.open(tester, cards: {'Chat': 'cat'});
    final card = (await screens.cards()).single;
    await screens.push((deck) => CardEditorScreen(deck: deck, card: card));

    expect(find.text('Edit card'), findsOneWidget);
    expect(find.text('Save'), findsOneWidget);
    expect(find.text('Save and next card'), findsNothing);

    await screens.tap(find.byTooltip('Delete card'));
    expect(find.text('Delete this card?'), findsOneWidget);
    // The confirmation keeps its cancel, and the delete comes last, below it.
    expect(
      tester.getRect(find.text('Cancel')).bottom,
      lessThanOrEqualTo(tester.getRect(find.text('Delete')).top),
    );
    await screens.tap(find.text('Delete'));

    expect(find.byType(CardEditorScreen), findsNothing);
    expect(await _stored(screens), isEmpty);
    await screens.close();
  });

  group('a duplicate front opens the duplicate sheet', () {
    Future<DeckScreens> collide(WidgetTester tester) async {
      final screens = await openNew(tester, cards: {'Chat': 'cat'});
      await screens.enter('Front', '  CHAT ');
      await screens.enter('Back', 'chat (talk)');
      await screens.tap(find.text('Save'));
      expect(find.text('This deck already has this card'), findsOneWidget);
      expect(
        find.text('Case and spacing are ignored when comparing.'),
        findsOneWidget,
      );
      // The existing card, in the same split preview as the editor's.
      expect(
        find.descendant(
          of: find.byType(BottomSheet),
          matching: find.byType(CardPreview),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byType(BottomSheet),
          matching: find.text('cat'),
        ),
        findsOneWidget,
      );
      return screens;
    }

    testWidgets('Add anyway stores the second card beside the first', (
      tester,
    ) async {
      final screens = await collide(tester);

      await screens.tap(find.text('Add anyway'));

      expect(find.byType(CardEditorScreen), findsNothing);
      expect(await _stored(screens), [
        ('Chat', 'cat'),
        ('  CHAT ', 'chat (talk)'),
      ]);
      await screens.close();
    });

    testWidgets('Open existing card opens it and stores nothing', (
      tester,
    ) async {
      final screens = await collide(tester);

      await screens.tap(find.text('Open existing card'));

      expect(find.text('Edit card'), findsOneWidget);
      expect(find.widgetWithText(TextField, 'Chat'), findsOneWidget);
      expect(find.widgetWithText(TextField, 'cat'), findsOneWidget);
      expect(await _stored(screens), [('Chat', 'cat')]);
      await screens.close();
    });

    testWidgets(
      'the sheet offers no cancel, and dismissing it returns to the editor and stores nothing',
      (tester) async {
        final screens = await collide(tester);
        final actions = find.descendant(
          of: find.byType(BottomSheet),
          matching: find.byType(AppButton),
        );
        // Control: the finder reaches the sheet's actions.
        expect(actions, findsNWidgets(2));
        expect(
          find.descendant(
            of: find.byType(BottomSheet),
            matching: find.text('Cancel'),
          ),
          findsNothing,
        );

        await tester.tapAt(const Offset(20, 20));
        await tester.pumpAndSettle();

        expect(find.byType(BottomSheet), findsNothing);
        expect(find.text('Add card'), findsOneWidget);
        expect(find.widgetWithText(TextField, 'chat (talk)'), findsOneWidget);
        expect(await _stored(screens), [('Chat', 'cat')]);
        await screens.close();
      },
    );
  });
}
