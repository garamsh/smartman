import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';

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

/// A card's question on its row, with its answer behind a bar unless
/// [shown]; a tap calls [onToggle], whose owner decides what [shown] becomes.
/// A long-press, or a screen reader's action, opens the card with [onEdit].
class CardAnswerRow extends StatelessWidget {
  const CardAnswerRow({
    super.key,
    required this.front,
    required this.back,
    required this.shown,
    required this.onToggle,
    required this.onEdit,
  });

  final String front;
  final String back;
  final bool shown;
  final VoidCallback onToggle;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colors = AppColors.of(context);
    return Semantics(
      container: true,
      button: true,
      label: shown
          ? l10n.cardAnswerShown(front, back)
          : l10n.cardAnswerHidden(front),
      onTapHint: shown ? l10n.hideAnswer : l10n.showAnswer,
      customSemanticsActions: {
        CustomSemanticsAction(label: l10n.editCard): onEdit,
      },
      excludeSemantics: true,
      child: AppRowSurface(
        onTap: onToggle,
        onLongPress: onEdit,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: AppSize.cta + 4),
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpace.s16,
              vertical: AppSpace.s12,
            ),
            child: Row(
              spacing: AppSpace.s12,
              children: [
                Expanded(child: Text(front, style: AppType.bodyStrong)),
                if (shown)
                  Expanded(
                    child: Text(
                      back,
                      textAlign: TextAlign.end,
                      style: AppType.secondary.copyWith(color: colors.ink2),
                    ),
                  )
                else
                  Container(
                    width: AppSize.cta * 2 - AppSpace.s16,
                    height: AppSpace.s24 - 2,
                    decoration: BoxDecoration(
                      color: colors.hairline,
                      borderRadius: BorderRadius.circular(AppSpace.s8),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
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
