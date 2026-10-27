import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
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

/// Each text [span] draws, with its colour and the fill of its own it is
/// drawn on, if any, a child's inherited from its parent.
Iterable<({String text, Color colour, Color? fill})> _runs(
  InlineSpan span,
  Color? colour,
  Color? fill,
) sync* {
  final own = span.style?.color ?? colour;
  final ownFill = span.style?.backgroundColor ?? fill;
  if (span is TextSpan) {
    final text = span.text ?? '';
    if (own != null && text.trim().isNotEmpty) {
      yield (text: text, colour: own, fill: ownFill);
    }
    for (final child in span.children ?? const <InlineSpan>[]) {
      yield* _runs(child, own, ownFill);
    }
  }
}

/// Each part of [span] under 4.5:1 on what it is drawn on: its own fill over
/// the opaque [ground], or [ground]. A part drawn in the colour of its own
/// fill, or fully transparent, is a mask, such as an unrevealed blank, and
/// not text.
List<String> _unreadable(InlineSpan span, Color ground) => [
  for (final (:text, :colour, :fill) in _runs(span, null, null))
    if (fill != colour && colour.a > 0)
      if (fill == null ? ground : over(fill, ground) case final under)
        if (contrast(over(colour, under), under) < 4.5)
          '"$text" of "${span.toPlainText()}" in $colour on $under',
];

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
    expect(_unreadable((element.widget as RichText).text, ground), isEmpty);
  }
}

/// What a widget paints under its children over [rect] on screen: a fill of
/// [colour], or a photo when [colour] is null.
typedef _Layer = ({Rect rect, Color? colour});

/// Where [box] is laid out on screen.
Rect _rectOf(RenderBox box) =>
    MatrixUtils.transformRect(box.getTransformTo(null), Offset.zero & box.size);

/// The part of [element]'s render box left on [screen] by the clips and the
/// scrolling viewports around it: empty when it is scrolled or clipped away.
Rect _shown(Element element, Rect screen) {
  final box = element.renderObject! as RenderBox;
  var shown = _rectOf(box).intersect(screen);
  for (var parent = box.parent; parent != null; parent = parent.parent) {
    if (parent is RenderBox &&
        (parent is RenderClipRect ||
            parent is RenderClipRRect ||
            parent is RenderClipPath ||
            parent is RenderAbstractViewport)) {
      shown = shown.intersect(_rectOf(parent));
    }
  }
  return shown.width > 0 && shown.height > 0 ? shown : Rect.zero;
}

/// The fill or photo [element]'s widget paints under its children on
/// [screen], if any.
_Layer? _layerOf(Element element, Rect screen) {
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
  final shown = _shown(element, screen);
  return shown.isEmpty ? null : (rect: shown, colour: colour);
}

/// The text [element] draws, if it draws one.
InlineSpan? _textOf(Element element) => switch (element.widget) {
  RichText(:final text) => text,
  EditableText(:final controller, :final style) => TextSpan(
    text: controller.text,
    style: style,
  ),
  _ => null,
};

/// Whether [element] is inside a control marked disabled. Its text is left
/// out, as `textContrastGuideline` leaves out a disabled node's: WCAG 1.4.3
/// exempts an inactive control.
bool _disabled(Element element) {
  var disabled = false;
  element.visitAncestorElements((ancestor) {
    final widget = ancestor.widget;
    disabled = widget is Semantics && widget.properties.enabled == false;
    return !disabled;
  });
  return disabled;
}

/// Expects every text on screen at 4.5:1 or more on what is painted under
/// it: the last fill or photo drawn before it over the centre of its shown
/// part, with each translucent fill drawn over that since. Text scrolled or
/// clipped off screen is not on it; an icon's glyph and a disabled control's
/// text are left out.
///
/// A text with no opaque fill under it fails, and so does one over a photo
/// unless it is in [overPhoto]. Each text in [failing], a known failure, must
/// be found and still fail. Unlike `textContrastGuideline`, this also fails
/// text drawn in the colour of what is under it.
void expectScreenTextReadable(
  WidgetTester tester, {
  Set<String> overPhoto = const {},
  Set<String> failing = const {},
}) {
  final screen =
      Offset.zero & (tester.view.physicalSize / tester.view.devicePixelRatio);
  final layers = <_Layer>[];
  final foundOverPhoto = <String>{};
  final stillFailing = <String>{};
  final unreadable = <String>[];
  var checked = 0;

  void visit(Element element) {
    final layer = _layerOf(element, screen);
    if (layer != null) layers.add(layer);
    final span = _textOf(element);
    final text = span?.toPlainText().trim() ?? '';
    final shown = span == null ? Rect.zero : _shown(element, screen);
    if (span != null && text.isNotEmpty && !shown.isEmpty) {
      final under = [
        for (final layer in layers)
          if (layer.rect.contains(shown.center)) layer,
      ];
      final ground = under.lastIndexWhere(
        (layer) => layer.colour == null || layer.colour!.a == 1,
      );
      if (ground == -1) {
        unreadable.add('"$text" has no opaque fill under it');
      } else if (_disabled(element)) {
        // Left out.
      } else if (under[ground].colour == null) {
        if (overPhoto.contains(text)) {
          foundOverPhoto.add(text);
        } else {
          unreadable.add('"$text" is drawn over a photo');
        }
      } else {
        var colour = under[ground].colour!;
        for (final layer in under.skip(ground + 1)) {
          colour = over(layer.colour!, colour);
        }
        final parts = _unreadable(span, colour);
        if (failing.contains(text)) {
          if (parts.isNotEmpty) stillFailing.add(text);
        } else {
          unreadable.addAll(parts);
        }
        checked++;
      }
    }
    if (element.widget is! Icon) element.debugVisitOnstageChildren(visit);
  }

  tester.binding.rootElement!.debugVisitOnstageChildren(visit);
  expect(unreadable, isEmpty, reason: 'texts under 4.5:1');
  expect(foundOverPhoto, overPhoto, reason: 'the texts over a photo');
  expect(stillFailing, failing, reason: 'the known failures, still failing');
  expect(checked, greaterThan(0), reason: 'a text was checked');
}
