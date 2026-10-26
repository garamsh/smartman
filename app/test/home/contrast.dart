import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smartman/design/app_button.dart';

/// [colour] drawn over the opaque [ground].
Color over(Color colour, Color ground) => Color.alphaBlend(colour, ground);

/// The WCAG 2.1 contrast ratio of two opaque colours.
double contrast(Color a, Color b) {
  final (lighter, darker) = a.computeLuminance() > b.computeLuminance()
      ? (a, b)
      : (b, a);
  return (lighter.computeLuminance() + 0.05) /
      (darker.computeLuminance() + 0.05);
}

/// Each colour [span] draws text in, a child's inherited from its parent.
Iterable<Color> _textColours(InlineSpan span, Color? inherited) sync* {
  final colour = span.style?.color ?? inherited;
  if (span is TextSpan) {
    if (colour != null && (span.text?.trim().isNotEmpty ?? false)) {
      yield colour;
    }
    for (final child in span.children ?? const <InlineSpan>[]) {
      yield* _textColours(child, colour);
    }
  }
}

/// Expects every text in [card], outside its buttons and icons, at 4.5:1 or
/// more on [ground]. Unlike `textContrastGuideline`, this also fails text
/// drawn in the colour of its ground, which leaves nothing on screen to
/// measure.
void expectTextReadable(WidgetTester tester, Finder card, Color ground) {
  final skipped = {
    for (final type in [AppButton, Icon])
      ...find
          .descendant(
            of: find.descendant(of: card, matching: find.byType(type)),
            matching: find.byType(RichText),
          )
          .evaluate(),
  };
  final texts = find
      .descendant(of: card, matching: find.byType(RichText))
      .evaluate()
      .where((text) => !skipped.contains(text))
      .toList();
  expect(texts, isNotEmpty);
  for (final element in texts) {
    final span = (element.widget as RichText).text;
    for (final colour in _textColours(span, null)) {
      expect(
        contrast(over(colour, ground), ground),
        greaterThanOrEqualTo(4.5),
        reason: '"${span.toPlainText()}" in $colour on $ground',
      );
    }
  }
}
