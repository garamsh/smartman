import 'package:flutter/material.dart';

import '../../design/theme.dart';
import '../../design/word_break.dart';
import '../../l10n/app_localizations.dart';
import 'audio_block.dart';
import 'card_list.dart';
import 'card_text.dart';
import 'content.dart';
import 'content_view.dart';
import 'image_block.dart';

/// A whole card's front, its blocks in order: a text block as its title, a
/// cloze as its sentence, a table as its table, an image as its photo and a
/// sound as its play control (ADR 0112),
/// with each blank empty, or each box hidden, or filled or revealed in place
/// when [revealed] (ADR 0068, ADR 0109), a table's span inside its cell's
/// text (ADR 0110). An empty blank keeps its answer's width, so filling it
/// moves nothing.
///
/// A cloze is in [style], centred, scaled down as far as [minFontSize] until
/// its widest word fits [width]. A table is in the body size, [width] wide.
/// Given [height] too, the whole front is scaled down to fit it. It reads as
/// [spokenContent] says, each empty blank as "빈칸".
class WholeCardView extends StatelessWidget {
  const WholeCardView(
    this.blocks, {
    super.key,
    required this.revealed,
    required this.style,
    this.minFontSize,
    this.width,
    this.height,
  });

  final List<Content> blocks;
  final bool revealed;
  final TextStyle style;
  final double? minFontSize;
  final double? width;
  final double? height;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final column = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: AppSpace.s12,
      children: [
        for (final block in blocks)
          switch (block) {
            TextContent(:final text) => Text(
              text,
              textAlign: TextAlign.center,
              style: _titleStyle,
            ),
            ClozeContent() => _cloze(context, block),
            TableContent() => _table(context, block),
            SensesContent() => Text.rich(
              sensesSpan(block),
              textAlign: TextAlign.center,
              style: style,
            ),
            // Inside [width] and [height] itself, so the photo alone is
            // not scaled down with the face and its boxes' chrome stays
            // its size.
            ImageContent() => ImageBlockView(
              block,
              revealed: revealed,
              width: this.width,
              maxHeight: height,
            ),
            AudioContent() => Center(child: AudioBlockView(block)),
            UnsupportedContent(:final type) => Text(
              l10n.unsupportedContent(type),
              textAlign: TextAlign.center,
              style: AppType.secondary.copyWith(fontStyle: FontStyle.italic),
            ),
          },
      ],
    );
    final width = this.width;
    return Semantics(
      container: true,
      label: spokenContent(l10n, blocks, revealed: revealed),
      excludeSemantics: true,
      child: width == null
          ? column
          : height == null
          ? SizedBox(width: width, child: column)
          : FittedBox(
              fit: BoxFit.scaleDown,
              child: SizedBox(width: width, child: column),
            ),
    );
  }

  /// A text block's style: the headline on a card, or, in a style smaller
  /// than it such as a list row's, that style in bold, so a row keeps its
  /// screen's sizes (#454).
  TextStyle get _titleStyle =>
      (style.fontSize ?? 0) < (AppType.headline.fontSize ?? 0)
      ? style.copyWith(fontWeight: FontWeight.w700)
      : AppType.headline.copyWith(color: style.color);

  Widget _cloze(BuildContext context, ClozeContent cloze) {
    final parts = cloze.text.split(clozeBlank);
    final span = TextSpan(
      children: [
        for (final (index, part) in parts.indexed) ...[
          // Korean breaks only between words (#454).
          TextSpan(text: keepWords(part)),
          if (index < cloze.answers.length)
            _blank(context, cloze.answers[index]),
        ],
      ],
    );
    final width = this.width;
    final minFontSize = this.minFontSize;
    if (width == null || minFontSize == null) {
      return Text.rich(span, style: style, textAlign: TextAlign.center);
    }
    return CardText(
      cloze.filled,
      span: span,
      style: style,
      minFontSize: minFontSize,
      width: width,
    );
  }

  Widget _table(BuildContext context, TableContent table) {
    final colors = AppColors.of(context);
    final cell = AppType.body.copyWith(color: style.color);
    final header = cell.copyWith(fontWeight: FontWeight.w700);
    Widget padded(Widget child) => Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpace.s8,
        vertical: AppSpace.s4,
      ),
      child: child,
    );
    return Table(
      border: TableBorder.all(color: colors.outline),
      defaultVerticalAlignment: TableCellVerticalAlignment.middle,
      children: [
        TableRow(
          decoration: BoxDecoration(color: colors.ground),
          children: [
            for (final text in table.columns)
              padded(Text(text, style: header, textAlign: TextAlign.center)),
          ],
        ),
        for (final (row, cells) in table.rows.indexed)
          TableRow(
            children: [
              for (final (column, _) in cells.indexed)
                padded(
                  Text.rich(
                    TextSpan(
                      children: [
                        for (final run in table.cellRuns(row, column))
                          run.blank
                              ? _blank(context, run.text)
                              : TextSpan(text: run.text),
                      ],
                    ),
                    // Each row starts with its header.
                    style: column == 0 ? header : cell,
                    textAlign: TextAlign.center,
                  ),
                ),
            ],
          ),
      ],
    );
  }

  /// A blank of [answer]: an empty gap of the answer's width over a muted
  /// underline, so hidden content shows as nothing (#454), or filled on the
  /// brand tint.
  TextSpan _blank(BuildContext context, String answer) {
    final colors = AppColors.of(context);
    return TextSpan(
      text: ' ${keepWords(answer)} ',
      style: revealed
          ? TextStyle(backgroundColor: colors.brandTint)
          : TextStyle(
              color: colors.muted.withValues(alpha: 0),
              decoration: TextDecoration.underline,
              decorationColor: colors.muted,
            ),
    );
  }
}
