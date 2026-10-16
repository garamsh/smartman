import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../shared/l10n/app_localizations.dart';
import '../../shared/theme.dart';
import '../../shared/ui/card_text.dart';
import 'content.dart';

/// A card side's content blocks, in order, each through its block widget.
///
/// With [maxLines], the blocks run together as one paragraph cut to that many
/// lines with an ellipsis.
///
/// With [fit], the text is centred and scaled down from [style]'s size as far
/// as the fit's floor until its widest word fits the fit's width, so it
/// breaks only between words ([CardText]).
class ContentView extends StatelessWidget {
  const ContentView(
    this.blocks, {
    super.key,
    this.style,
    this.maxLines,
    this.fit,
  });

  final List<Content> blocks;
  final TextStyle? style;
  final int? maxLines;
  final ({double minFontSize, double width})? fit;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final fit = this.fit;
    final style = this.style;
    if (maxLines case final maxLines?) {
      final fitted = fit == null || style == null
          ? style
          : fittedStyle(
              context,
              [for (final block in blocks) _plain(l10n, block)].join(' '),
              style: style,
              minFontSize: fit.minFontSize,
              width: fit.width,
            );
      return Text.rich(
        TextSpan(
          children: [
            for (final (index, block) in blocks.indexed) ...[
              if (index > 0) const TextSpan(text: '\n'),
              _span(l10n, block),
            ],
          ],
        ),
        style: fitted,
        maxLines: maxLines,
        overflow: TextOverflow.ellipsis,
        textAlign: fit == null ? null : TextAlign.center,
      );
    }
    return Column(
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
            UnsupportedContent(:final type) => _UnsupportedBlock(
              label: l10n.unsupportedContent(type),
            ),
          },
      ],
    );
  }

  String _plain(AppLocalizations l10n, Content block) => switch (block) {
    TextContent(:final text) => text,
    UnsupportedContent(:final type) => l10n.unsupportedContent(type),
  };

  InlineSpan _span(AppLocalizations l10n, Content block) => switch (block) {
    TextContent(:final text) => TextSpan(text: text),
    UnsupportedContent(:final type) => TextSpan(
      text: l10n.unsupportedContent(type),
      style: const TextStyle(fontStyle: FontStyle.italic),
    ),
  };
}

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
