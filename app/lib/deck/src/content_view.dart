import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../design/theme.dart';
import '../../l10n/app_localizations.dart';
import 'card_text.dart';
import 'content.dart';
import 'image_block.dart';
import 'whole_card_view.dart';

/// A card side's content blocks, in order, each through its block widget.
///
/// With [fit], the text is centred and scaled down from [style]'s size as far
/// as the fit's floor until its widest word fits the fit's width, so it
/// breaks only between words ([CardText]). With the fit's height too, the
/// blocks run together as one paragraph, scaled down further, as far as the
/// floor, until it fits that height, and cut with an ellipsis past the lines
/// that fit there ([fittedToBox]); a side that holds a photo is laid out
/// block by block instead, its photo inside the fit, and scaled down as a
/// whole to fit that height (ADR 0109).
class ContentView extends StatelessWidget {
  const ContentView(this.blocks, {super.key, this.style, this.fit});

  final List<Content> blocks;
  final TextStyle? style;
  final ({double minFontSize, double width, double? height})? fit;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final fit = this.fit;
    final style = this.style;
    final hasImage = blocks.any((block) => block is ImageContent);
    if (fit case (:final minFontSize, :final width, :final height?)
        when !hasImage) {
      final span = contentSpan(l10n, blocks);
      final paragraph = DefaultTextStyle.of(context).style.merge(style);
      final fitted = fittedToBox(
        span,
        [for (final block in blocks) _plain(l10n, block)].join(' '),
        style: paragraph,
        minFontSize: minFontSize,
        width: width,
        height: height,
        textScaler: MediaQuery.textScalerOf(context),
        textDirection: Directionality.of(context),
      );
      return Text.rich(
        span,
        style: fitted.style,
        maxLines: fitted.maxLines,
        overflow: TextOverflow.ellipsis,
        textAlign: TextAlign.center,
      );
    }
    final column = Column(
      crossAxisAlignment: fit == null
          ? CrossAxisAlignment.start
          : CrossAxisAlignment.center,
      spacing: _blockGap,
      children: [
        for (final block in blocks)
          switch (block) {
            TextContent(:final text) when fit != null && style != null =>
              CardText(
                text,
                style: style,
                minFontSize: fit.minFontSize,
                width: fit.width,
              ),
            TextContent(:final text) => Text(text, style: style),
            SensesContent(:final lines) when fit != null && style != null =>
              CardText(
                lines,
                span: sensesSpan(block),
                style: style,
                minFontSize: fit.minFontSize,
                width: fit.width,
              ),
            SensesContent() => Text.rich(sensesSpan(block), style: style),
            ClozeContent() || TableContent() => WholeCardView(
              [block],
              revealed: true,
              style: style ?? AppType.body,
            ),
            ImageContent() => ImageBlockView(
              block,
              revealed: true,
              width: fit?.width,
              maxHeight: fit?.height,
            ),
            UnsupportedContent(:final type) => _UnsupportedBlock(
              label: l10n.unsupportedContent(type),
            ),
          },
      ],
    );
    return switch (fit) {
      (:final width, height: _?, minFontSize: _) => FittedBox(
        fit: BoxFit.scaleDown,
        child: SizedBox(width: width, child: column),
      ),
      _ => column,
    };
  }

  String _plain(AppLocalizations l10n, Content block) => switch (block) {
    TextContent(:final text) => text,
    ClozeContent(:final filled) || TableContent(:final filled) => filled,
    SensesContent(:final lines) => lines,
    ImageContent() => l10n.blockImage,
    UnsupportedContent(:final type) => l10n.unsupportedContent(type),
  };
}

String _same(String text) => text;

/// [blocks] run together as one paragraph, a line apart: a text block as
/// written, a cloze or a table filled, a senses block as [sensesSpan] draws
/// it, a photo as "사진", and a block this version cannot show named by its
/// type. [wrap] is
/// applied to each piece of text, such as a list's line-breaking rule.
InlineSpan contentSpan(
  AppLocalizations l10n,
  List<Content> blocks, {
  String Function(String text) wrap = _same,
}) => TextSpan(
  children: [
    for (final (index, block) in blocks.indexed) ...[
      if (index > 0) const TextSpan(text: '\n'),
      switch (block) {
        TextContent(:final text) => TextSpan(text: wrap(text)),
        ClozeContent(:final filled) ||
        TableContent(:final filled) => TextSpan(text: wrap(filled)),
        SensesContent() => sensesSpan(block, wrap: wrap),
        ImageContent() => TextSpan(text: wrap(l10n.blockImage)),
        UnsupportedContent(:final type) => TextSpan(
          text: l10n.unsupportedContent(type),
          style: const TextStyle(fontStyle: FontStyle.italic),
        ),
      },
    ],
  ],
);

/// [senses] one per line, each label in its brackets as its own span with a
/// gap of [AppSpace.s4] after it, narrower than a word space, then the
/// meaning: `[명]` 사과 (ADR 0075). The gap is the closing bracket's letter
/// spacing, so the line stays one paragraph that fits and wraps as text.
InlineSpan sensesSpan(
  SensesContent senses, {
  String Function(String text) wrap = _same,
}) => TextSpan(
  children: [
    for (final (index, sense) in senses.senses.indexed) ...[
      if (index > 0) const TextSpan(text: '\n'),
      for (final label in sense.labels) ...[
        TextSpan(text: '[${label.shown}'),
        const TextSpan(
          text: ']',
          style: TextStyle(letterSpacing: AppSpace.s4),
        ),
      ],
      TextSpan(text: wrap(sense.meaning)),
    ],
  ],
);

/// Space between two content blocks, and inside a block's placeholder.
const _blockGap = AppSpace.s8;

/// The labelled placeholder for a block this version cannot show.
class _UnsupportedBlock extends StatelessWidget {
  const _UnsupportedBlock({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border.all(color: theme.colorScheme.outline),
        borderRadius: BorderRadius.circular(_blockGap),
      ),
      child: Padding(
        padding: const EdgeInsets.all(_blockGap),
        child: Row(
          spacing: _blockGap,
          children: [
            Icon(
              LucideIcons.circleQuestionMark,
              color: theme.colorScheme.onSurfaceVariant,
            ),
            Expanded(
              child: Text(
                label,
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontStyle: FontStyle.italic,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
