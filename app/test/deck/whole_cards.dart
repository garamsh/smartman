import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

/// Each blank of a whole card drawn under [of], by its answer: true where it
/// is filled on its fill, false where it is empty, its answer not drawn over
/// its underline.
Map<String, bool> blanksUnder(Finder of) {
  final blanks = <String, bool>{};
  for (final element
      in find.descendant(of: of, matching: find.byType(RichText)).evaluate()) {
    (element.widget as RichText).text.visitChildren((span) {
      final style = span.style;
      if (span is! TextSpan || span.text == null || style == null) return true;
      if (style.backgroundColor != null) {
        blanks[span.text!.trim()] = style.color != style.backgroundColor;
      } else if (isEmptyBlank(style)) {
        blanks[span.text!.trim()] = false;
      }
      return true;
    });
  }
  return blanks;
}

/// Whether [style] draws an empty blank: its text invisible over an
/// underline, with no fill.
bool isEmptyBlank(TextStyle style) =>
    style.backgroundColor == null &&
    style.color?.a == 0 &&
    (style.decoration?.contains(TextDecoration.underline) ?? false);
