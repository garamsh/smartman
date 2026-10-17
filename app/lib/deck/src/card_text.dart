import 'dart:math';

import 'package:flutter/material.dart';

/// A card side's text, centred, in [style] scaled down as far as
/// [minFontSize] until its widest word fits [width], so lines break only
/// between words. Only a word wider than [width] at [minFontSize] breaks
/// inside itself. With [maxLines] the text is cut to that many lines with an
/// ellipsis.
///
/// [width] is the width the text is laid out in; the caller passes it, since
/// a card measures its halves' intrinsic heights, which a layout builder here
/// could not answer.
class CardText extends StatelessWidget {
  const CardText(
    this.text, {
    super.key,
    required this.style,
    required this.minFontSize,
    required this.width,
    this.maxLines,
  });

  final String text;
  final TextStyle style;
  final double minFontSize;
  final double width;
  final int? maxLines;

  @override
  Widget build(BuildContext context) {
    final size = fittedFontSize(
      text,
      style: style,
      minFontSize: minFontSize,
      width: width,
      textScaler: MediaQuery.textScalerOf(context),
      textDirection: Directionality.of(context),
    );
    return Text(
      text,
      style: style.copyWith(fontSize: size),
      textAlign: TextAlign.center,
      maxLines: maxLines,
      overflow: maxLines == null ? null : TextOverflow.ellipsis,
    );
  }
}

/// The largest whole size from [style]'s down to [minFontSize] at which the
/// widest word of [text] fits [width]; [minFontSize] when none does.
double fittedFontSize(
  String text, {
  required TextStyle style,
  required double minFontSize,
  required double width,
  required TextScaler textScaler,
  required TextDirection textDirection,
}) {
  final words = text.split(RegExp(r'\s+')).where((word) => word.isNotEmpty);
  final largest = style.fontSize ?? minFontSize;
  for (var size = largest; size > minFontSize; size -= 1) {
    if (_widestWord(
          words,
          style.copyWith(fontSize: size),
          textScaler,
          textDirection,
        ) <=
        width) {
      return size;
    }
  }
  return minFontSize;
}

/// The size and lines that fit [span], in [style], into a box [width] wide
/// and [height] high: the largest whole size from [fittedFontSize]'s down to
/// [minFontSize] at which the whole text fits, with as many lines as it takes;
/// otherwise [minFontSize], with as many lines as fit [height], at least one,
/// past which the text is cut. [plain] is the span's text, whose widest word
/// sets the largest size.
({double fontSize, int maxLines}) fittedToBox(
  InlineSpan span,
  String plain, {
  required TextStyle style,
  required double minFontSize,
  required double width,
  required double height,
  required TextScaler textScaler,
  required TextDirection textDirection,
}) {
  final largest = fittedFontSize(
    plain,
    style: style,
    minFontSize: minFontSize,
    width: width,
    textScaler: textScaler,
    textDirection: textDirection,
  );
  for (var size = largest; ; size -= 1) {
    final floor = size <= minFontSize;
    final fontSize = floor ? minFontSize : size;
    final painter = TextPainter(
      text: TextSpan(
        style: style.copyWith(fontSize: fontSize),
        children: [span],
      ),
      textAlign: TextAlign.center,
      textDirection: textDirection,
      textScaler: textScaler,
    )..layout(maxWidth: width);
    final fits = painter.height <= height;
    final lines = fits
        ? painter.computeLineMetrics().length
        : max(1, (height / painter.preferredLineHeight).floor());
    painter.dispose();
    if (fits || floor) return (fontSize: fontSize, maxLines: max(1, lines));
  }
}

double _widestWord(
  Iterable<String> words,
  TextStyle style,
  TextScaler textScaler,
  TextDirection textDirection,
) {
  var widest = 0.0;
  for (final word in words) {
    final painter = TextPainter(
      text: TextSpan(text: word, style: style),
      textDirection: textDirection,
      textScaler: textScaler,
      maxLines: 1,
    )..layout();
    if (painter.width > widest) widest = painter.width;
    painter.dispose();
  }
  return widest;
}
