import 'package:flutter/material.dart';

import '../../design/theme.dart';
import '../../l10n/app_localizations.dart';
import 'card_markup.dart';
import 'card_text.dart';

/// A whole card's front: its sentence, or its table, with each blank empty,
/// or filled in place when [revealed] (ADR 0068). An empty blank keeps its
/// answer's width, so filling it moves nothing.
///
/// A sentence is in [style], centred, scaled down as far as [minFontSize]
/// until its widest word fits [width], and, given [height] too, until it
/// fits that height, cut there with an ellipsis. A table is in the body
/// size, [width] wide, scaled down as a whole to fit [height] when given.
/// It reads as [spoken] says, blanks as "빈칸" until revealed.
class WholeCardView extends StatelessWidget {
  const WholeCardView(
    this.text, {
    super.key,
    required this.revealed,
    required this.style,
    this.minFontSize,
    this.width,
    this.height,
  });

  final String text;
  final bool revealed;
  final TextStyle style;
  final double? minFontSize;
  final double? width;
  final double? height;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final table = tableOf(text);
    return Semantics(
      container: true,
      label: spoken(text, revealed: revealed, blank: l10n.blank),
      excludeSemantics: true,
      child: table == null ? _sentence(context) : _table(context, table),
    );
  }

  Widget _sentence(BuildContext context) {
    final span = _span(context, text);
    final width = this.width;
    final minFontSize = this.minFontSize;
    final height = this.height;
    final textScaler = MediaQuery.textScalerOf(context);
    final textDirection = Directionality.of(context);
    if (width == null || minFontSize == null) {
      return Text.rich(span, style: style, textAlign: TextAlign.center);
    }
    if (height == null) {
      return CardText(
        filled(text),
        span: span,
        style: style,
        minFontSize: minFontSize,
        width: width,
      );
    }
    final fitted = fittedToBox(
      span,
      filled(text),
      style: DefaultTextStyle.of(context).style.merge(style),
      minFontSize: minFontSize,
      width: width,
      height: height,
      textScaler: textScaler,
      textDirection: textDirection,
    );
    return Text.rich(
      span,
      style: fitted.style,
      maxLines: fitted.maxLines,
      overflow: TextOverflow.ellipsis,
      textAlign: TextAlign.center,
    );
  }

  Widget _table(BuildContext context, MarkupTable table) {
    final colors = AppColors.of(context);
    final cell = AppType.body.copyWith(color: style.color);
    final grid = Table(
      border: TableBorder.all(color: colors.outline),
      defaultVerticalAlignment: TableCellVerticalAlignment.middle,
      children: [
        for (final (index, row) in table.rows.indexed)
          TableRow(
            decoration: index < table.headerRows
                ? BoxDecoration(color: colors.ground)
                : null,
            children: [
              for (final text in row)
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpace.s8,
                    vertical: AppSpace.s4,
                  ),
                  child: Text.rich(
                    _span(context, text),
                    style: index < table.headerRows
                        ? cell.copyWith(fontWeight: FontWeight.w700)
                        : cell,
                    textAlign: TextAlign.center,
                  ),
                ),
            ],
          ),
      ],
    );
    final width = this.width;
    if (width == null) return grid;
    final sized = SizedBox(width: width, child: grid);
    return height == null
        ? sized
        : FittedBox(fit: BoxFit.scaleDown, child: sized);
  }

  /// [line]'s runs, an empty blank as its answer in the hairline colour on
  /// the hairline fill, so it does not show, and a filled one on the brand
  /// tint.
  TextSpan _span(BuildContext context, String line) {
    final colors = AppColors.of(context);
    return TextSpan(
      children: [
        for (final run in runsOf(line))
          switch (run) {
            PlainRun(:final text) => TextSpan(text: text),
            BlankRun(:final answer) => TextSpan(
              text: ' $answer ',
              style: revealed
                  ? TextStyle(backgroundColor: colors.brandTint)
                  : TextStyle(
                      color: colors.hairline,
                      backgroundColor: colors.hairline,
                    ),
            ),
          },
      ],
    );
  }
}
