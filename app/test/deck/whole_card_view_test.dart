import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smartman/deck/src/content.dart';
import 'package:smartman/deck/src/whole_card_view.dart';
import 'package:smartman/design/theme.dart';

import '../design/harness.dart';
import 'whole_cards.dart';

void main() {
  const cloze = ClozeContent('The capital is $clozeBlank today', ['Paris']);

  /// The blank's span under the card.
  TextSpan blankSpan(WidgetTester tester) {
    TextSpan? found;
    for (final paragraph in tester.widgetList<RichText>(
      find.descendant(
        of: find.byType(WholeCardView),
        matching: find.byType(RichText),
      ),
    )) {
      paragraph.text.visitChildren((span) {
        if (span is TextSpan && blankAnswer(span.text ?? '') == 'Paris') {
          found = span;
        }
        return true;
      });
    }
    return found ?? (throw StateError('no blank drawn'));
  }

  for (final MapEntry(key: themeMode, value: colors) in themeModes.entries) {
    testWidgets('an empty blank is a gap of its answer\'s width over a muted '
        'underline, with no fill, and a filled one keeps the brand tint, in '
        '${themeMode.name}', (tester) async {
      Future<Size> pump({required bool revealed}) async {
        await pumpComponent(
          tester,
          WholeCardView(const [cloze], revealed: revealed, style: AppType.back),
          themeMode: themeMode,
        );
        return tester.getSize(
          find.descendant(
            of: find.byType(WholeCardView),
            matching: find.byType(RichText),
          ),
        );
      }

      final empty = await pump(revealed: false);
      final style = blankSpan(tester).style!;
      expect(style.backgroundColor, isNull, reason: 'no grey bar');
      expect(style.color?.a, 0, reason: 'the answer is not drawn');
      expect(style.decoration, TextDecoration.underline);
      expect(style.decorationColor, colors.muted);
      expect(isEmptyBlank(style), isTrue);
      expect(blanksUnder(find.byType(WholeCardView)), {'Paris': false});

      // Control: filled, the same span is drawn on the brand tint, and the
      // line keeps its size, so the gap was the answer's width.
      final filled = await pump(revealed: true);
      expect(blankSpan(tester).style!.backgroundColor, colors.brandTint);
      expect(blanksUnder(find.byType(WholeCardView)), {'Paris': true});
      expect(filled, empty);
    });
  }

  testWidgets('a Korean cloze sentence breaks only between words, its blank '
      'included, and reads as written (#454)', (tester) async {
    const korean = ClozeContent(
      '낮에는 친구들과 함께 춤을 추고 밤에는 $clozeBlank 노래를 부르며 하루를 보냈어요',
      ['조용히'],
    );
    await pumpComponent(
      tester,
      const SizedBox(
        width: 180,
        child: WholeCardView([korean], revealed: false, style: AppType.back),
      ),
      themeMode: ThemeMode.light,
    );
    final paragraph = tester.renderObject<RenderParagraph>(
      find.descendant(
        of: find.byType(WholeCardView),
        matching: find.byType(RichText),
      ),
    );
    final plain = paragraph.text.toPlainText();
    final lines = TextPainter(
      text: paragraph.text,
      textDirection: paragraph.textDirection,
      textScaler: paragraph.textScaler,
    )..layout(maxWidth: paragraph.size.width);
    addTearDown(lines.dispose);
    final ends = <int>[];
    for (var offset = 0; offset < plain.length;) {
      offset = lines.getLineBoundary(TextPosition(offset: offset)).end;
      ends.add(offset);
    }
    // It wraps at this width, so where it breaks is tested.
    expect(ends.length, greaterThan(2));
    bool space(String char) => char == ' ' || char == '\u00a0';
    for (final end in ends.take(ends.length - 1)) {
      expect(
        space(plain[end - 1]) || space(plain[end]),
        isTrue,
        reason: 'a break at $end in "$plain"',
      );
    }
    // The joiners are not read: the card reads as its words.
    expect(find.bySemanticsLabel(RegExp('^낮에는 친구들과 함께 춤을')), findsOneWidget);
  });
}
