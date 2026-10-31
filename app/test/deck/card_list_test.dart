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
                  back: const [TextContent('3인칭 재귀칭')],
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
}
