import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smartman/deck/deck.dart';
import 'package:smartman/design/theme.dart';
import 'package:smartman/l10n/app_localizations.dart';

import 'whole_cards.dart';

void main() {
  testWidgets(
    'a split row draws a cloze card as its front with its blanks filled, where a text card stays split',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: lightTheme,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('en'),
          home: const Scaffold(
            body: Column(
              children: [
                CardSplitRow(
                  key: Key('whole'),
                  front: [
                    ClozeContent('The capital of France is ___', ['Paris']),
                  ],
                  back: [TextContent('The capital of France is Paris')],
                ),
                CardSplitRow(
                  key: Key('plain'),
                  front: [TextContent('Chat')],
                  back: [TextContent('cat')],
                ),
              ],
            ),
          ),
        ),
      );

      final whole = find.byKey(const Key('whole'));
      expect(blanksUnder(whole), {'Paris': true});
      expect(
        find.descendant(of: whole, matching: find.byType(VerticalDivider)),
        findsNothing,
      );
      // Control: the text card keeps its two halves.
      final plain = find.byKey(const Key('plain'));
      expect(
        find.descendant(of: plain, matching: find.byType(VerticalDivider)),
        findsOneWidget,
      );
      expect(find.text('cat'), findsOneWidget);
    },
  );

  for (final shown in [false, true]) {
    testWidgets('a deck row draws a long Korean cloze sentence whole on a 390 wide phone, '
        'inside the row and broken only between words, with its blanks '
        '${shown ? 'filled' : 'empty'} (#477)', (tester) async {
      tester.view.physicalSize = const Size(390, 844) * 3;
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          theme: lightTheme,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('ko'),
          home: Scaffold(
            body: ListView(
              padding: const EdgeInsets.all(AppSpace.s16),
              children: [
                CardBackRow(
                  front: const [
                    ClozeContent(
                      '3인칭 재귀칭은 높임에서 $clozeBlank 를 쓰고 예사에서는 '
                      '$clozeBlank 를 쓰며 낮춤에서는 저를 쓰는데 이는 문장의 '
                      '주어를 다시 가리킬 때 쓰인다',
                      ['당신', '자기'],
                    ),
                  ],
                  back: const [],
                  shown: shown,
                  onOpen: () {},
                ),
              ],
            ),
          ),
        ),
      );

      final row = find.byType(CardBackRow);
      final paragraph = tester.renderObject<RenderParagraph>(
        find.descendant(of: row, matching: find.byType(RichText)),
      );
      final plain = paragraph.text.toPlainText();
      // The sentence laid out alone at the paragraph's width: its full
      // height and its lines.
      final whole = TextPainter(
        text: paragraph.text,
        textDirection: paragraph.textDirection,
        textScaler: paragraph.textScaler,
      )..layout(maxWidth: paragraph.size.width);
      addTearDown(whole.dispose);
      final ends = <int>[];
      for (var offset = 0; offset < plain.length;) {
        offset = whole.getLineBoundary(TextPosition(offset: offset)).end;
        ends.add(offset);
      }
      // It wraps at this width, so a cut or a break is tested.
      expect(ends.length, greaterThan(2));
      // Every line is laid out, and every line is inside the row.
      expect(paragraph.didExceedMaxLines, isFalse);
      expect(paragraph.size.height, greaterThanOrEqualTo(whole.height));
      final text = tester.getRect(
        find.descendant(of: row, matching: find.byType(RichText)),
      );
      final bounds = tester.getRect(row);
      expect(text.top, greaterThanOrEqualTo(bounds.top));
      expect(text.bottom, lessThanOrEqualTo(bounds.bottom));
      bool space(String char) => char == ' ' || char == ' ';
      for (final end in ends.take(ends.length - 1)) {
        expect(
          space(plain[end - 1]) || space(plain[end]),
          isTrue,
          reason: 'a break at $end in "$plain"',
        );
      }
    });
  }

  group('a whole card with a kept back', () {
    const cloze = ClozeContent('The capital is $clozeBlank', ['Paris']);
    const front = [cloze];
    const back = [TextContent('on the Seine')];

    Future<void> pump(WidgetTester tester, Widget row) => tester.pumpWidget(
      MaterialApp(
        theme: lightTheme,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('en'),
        home: Scaffold(body: row),
      ),
    );

    testWidgets('its split row draws it revealed, as the previous card does', (
      tester,
    ) async {
      await pump(tester, const CardSplitRow(front: front, back: back));
      expect(find.text('on the Seine'), findsOneWidget);
      expect(blanksUnder(find.byType(CardSplitRow)), {'Paris': true});
      expect(find.byType(VerticalDivider), findsNothing);
    });

    testWidgets('its deck row hides the back until shown, and reads it after '
        'the answer', (tester) async {
      Widget row(bool shown) =>
          CardBackRow(front: front, back: back, shown: shown, onOpen: () {});
      await pump(tester, row(false));
      expect(find.text('on the Seine'), findsNothing);
      expect(blanksUnder(find.byType(CardBackRow)), {'Paris': false});
      expect(
        find.bySemanticsLabel('The capital is blank, back hidden'),
        findsOneWidget,
      );

      await pump(tester, row(true));
      expect(find.text('on the Seine'), findsOneWidget);
      expect(blanksUnder(find.byType(CardBackRow)), {'Paris': true});
      expect(
        find.bySemanticsLabel(
          'The capital is blank, back The capital is Paris. on the Seine',
        ),
        findsOneWidget,
      );
    });

    testWidgets('a row draws the 칸 a framed card stores, a back in the 칸 it '
        'was written on', (tester) async {
      const cells = [
        BlankCell(cloze),
        TextCell(front: 'one'),
        TextCell(front: 'two', back: 'of two'),
      ];
      final sides = sidesOf(cells);
      await pump(
        tester,
        CardSplitRow(front: sides.front, back: sides.back, cells: cells),
      );
      double top(String text) => tester.getTopLeft(find.text(text)).dy;
      expect(top('one'), lessThan(top('two')));
      expect(top('two'), lessThan(top('of two')));
    });
  });
}
