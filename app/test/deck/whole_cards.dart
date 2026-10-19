import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

/// Each blank of a whole card drawn under [of], by its answer: true where it
/// is filled, false where it is empty, its answer drawn in its fill's colour.
Map<String, bool> blanksUnder(Finder of) {
  final blanks = <String, bool>{};
  for (final element
      in find.descendant(of: of, matching: find.byType(RichText)).evaluate()) {
    (element.widget as RichText).text.visitChildren((span) {
      final style = span.style;
      if (span is TextSpan &&
          span.text != null &&
          style?.backgroundColor != null) {
        blanks[span.text!.trim()] = style!.color != style.backgroundColor;
      }
      return true;
    });
  }
  return blanks;
}
