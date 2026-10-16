import 'package:flutter/material.dart';

import '../../design/app_list_row.dart';
import '../../design/theme.dart';
import '../../l10n/app_localizations.dart';
import 'content.dart';
import 'split_card.dart';

/// A card as two columns, front and back, split by a thin divider; read-only
/// without [onTap]. On its own it is a row on its rounded surface; [grouped]
/// it is one row of a group that draws the surface.
class CardSplitRow extends StatelessWidget {
  const CardSplitRow({
    super.key,
    required this.front,
    required this.back,
    this.onTap,
    this.grouped = false,
  });

  final String front;
  final String back;
  final VoidCallback? onTap;
  final bool grouped;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final content = SplitCard(
      centred: false,
      front: (context, _) => Text(front, style: AppType.label),
      back: (context, _) =>
          Text(back, style: AppType.secondary.copyWith(color: colors.ink2)),
    );
    final onTap = this.onTap;
    if (!grouped) return AppRowSurface(onTap: onTap, child: content);
    return onTap == null ? content : InkWell(onTap: onTap, child: content);
  }
}

/// One line of text for a card side; a block this version cannot show is
/// named by its type.
String describeContent(AppLocalizations l10n, List<Content> blocks) => blocks
    .map(
      (block) => switch (block) {
        TextContent(:final text) => text,
        UnsupportedContent(:final type) => l10n.unsupportedContent(type),
      },
    )
    .join(' ');
