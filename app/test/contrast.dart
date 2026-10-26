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

/// Expects each colour of [span] at 4.5:1 or more on the opaque [ground].
void _expectReadable(InlineSpan span, Color ground) {
  for (final colour in _textColours(span, null)) {
    expect(
      contrast(over(colour, ground), ground),
      greaterThanOrEqualTo(4.5),
      reason: '"${span.toPlainText()}" in $colour on $ground',
    );
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
    _expectReadable((element.widget as RichText).text, ground);
  }
}

/// What a widget paints under its children over [rect] on screen: a fill of
/// [colour], or a photo when [colour] is null.
typedef _Layer = ({Rect rect, Color? colour});

/// Where [element]'s render box is drawn on screen.
Rect _onScreen(Element element) {
  final box = element.renderObject! as RenderBox;
  return MatrixUtils.transformRect(
    box.getTransformTo(null),
    Offset.zero & box.size,
  );
}

/// The fill or photo [element]'s widget paints under its children, if any.
_Layer? _layerOf(Element element) {
  final Color? colour;
  switch (element.widget) {
    case ColoredBox(:final color):
    case PhysicalModel(:final color):
    case PhysicalShape(:final color):
      colour = color;
    case DecoratedBox(
          :final decoration,
          position: DecorationPosition.background,
        ) ||
        Ink(:final Decoration decoration):
      switch (decoration) {
        case BoxDecoration(image: _?) || ShapeDecoration(image: _?):
          colour = null;
        case BoxDecoration(:final color?) || ShapeDecoration(:final color?):
          colour = color;
        default:
          return null;
      }
    case RawImage():
      colour = null;
    default:
      return null;
  }
  if (colour != null && colour.a == 0) return null;
  final box = element.renderObject;
  if (box is! RenderBox || !box.hasSize) return null;
  return (rect: _onScreen(element), colour: colour);
}

/// The text [element] draws, if it is a text outside an icon.
InlineSpan? _textOf(Element element) => switch (element.widget) {
  RichText(:final text) => text,
  EditableText(:final controller, :final style) => TextSpan(
    text: controller.text,
    style: style,
  ),
  _ => null,
};

/// Expects every text on screen, an icon's glyph aside, at 4.5:1 or more on
/// what is painted under it: the last fill or photo drawn before it over its
/// centre, with each translucent fill drawn over that since. A text with no
/// opaque fill under it fails, and so does one over a photo unless it is in
/// [overPhoto], each of which must be found over one. Unlike
/// `textContrastGuideline`, this also fails text drawn in the colour of
/// what is under it.
void expectScreenTextReadable(
  WidgetTester tester, {
  Set<String> overPhoto = const {},
}) {
  final layers = <_Layer>[];
  final foundOverPhoto = <String>{};
  var checked = 0;

  void visit(Element element) {
    final layer = _layerOf(element);
    if (layer != null) layers.add(layer);
    final span = _textOf(element);
    final text = span?.toPlainText().trim() ?? '';
    if (span != null && text.isNotEmpty) {
      final centre = _onScreen(element).center;
      final under = [
        for (final layer in layers)
          if (layer.rect.contains(centre)) layer,
      ];
      final ground = under.lastIndexWhere(
        (layer) => layer.colour == null || layer.colour!.a == 1,
      );
      expect(ground, isNot(-1), reason: '"$text" has no opaque fill under it');
      if (under[ground].colour == null) {
        expect(
          overPhoto,
          contains(text),
          reason: '"$text" is drawn over a photo',
        );
        foundOverPhoto.add(text);
      } else {
        var colour = under[ground].colour!;
        for (final layer in under.skip(ground + 1)) {
          colour = over(layer.colour!, colour);
        }
        _expectReadable(span, colour);
        checked++;
      }
    }
    // An icon's glyph is a mark, not text.
    if (element.widget is! Icon) element.debugVisitOnstageChildren(visit);
  }

  tester.binding.rootElement!.debugVisitOnstageChildren(visit);
  expect(foundOverPhoto, overPhoto, reason: 'the texts over a photo');
  expect(checked, greaterThan(0), reason: 'a text was checked');
}
