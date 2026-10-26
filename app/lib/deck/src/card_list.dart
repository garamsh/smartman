import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../design/app_list_row.dart';
import '../../design/theme.dart';
import '../../l10n/app_localizations.dart';
import 'content.dart';
import 'content_view.dart';
import 'split_card.dart';
import 'whole_card_view.dart';

/// A card as two columns, front and back, split by a thin divider, or a
/// whole card's front with its blanks filled; read-only without [onTap]. On
/// its own it is a row on its rounded surface; [grouped] it is one row of a
/// group that draws the surface.
class CardSplitRow extends StatelessWidget {
  const CardSplitRow({
    super.key,
    required this.front,
    required this.back,
    this.onTap,
    this.grouped = false,
  });

  final List<Content> front;
  final List<Content> back;
  final VoidCallback? onTap;
  final bool grouped;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colors = AppColors.of(context);
    final content = isWholeCard(front)
        ? Padding(
            padding: const EdgeInsets.all(AppSpace.s16),
            child: WholeCardView(front, revealed: true, style: AppType.label),
          )
        : SplitCard(
            centred: false,
            front: (context, _) =>
                Text.rich(contentSpan(l10n, front), style: AppType.label),
            back: (context, _) => Text.rich(
              contentSpan(l10n, back),
              style: AppType.secondary.copyWith(color: colors.ink2),
            ),
          );
    final onTap = this.onTap;
    if (!grouped) return AppRowSurface(onTap: onTap, child: content);
    return onTap == null ? content : InkWell(onTap: onTap, child: content);
  }
}

/// A card's front on its row, with its back behind a bar unless
/// [shown], or a whole card's front with its blanks empty unless [shown]; a
/// tap calls [onToggle], whose owner decides what [shown] becomes. The pencil
/// at its end opens the card with [onEdit], and so do a long-press and a
/// screen reader's action on the row.
class CardBackRow extends StatelessWidget {
  const CardBackRow({
    super.key,
    required this.front,
    required this.back,
    required this.shown,
    required this.onToggle,
    required this.onEdit,
  });

  final List<Content> front;
  final List<Content> back;
  final bool shown;
  final VoidCallback onToggle;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colors = AppColors.of(context);
    final spokenFront = spokenContent(l10n, front, revealed: false);
    final spokenBack = describeContent(l10n, back);
    final radius = Radius.circular(AppRadius.row);
    return AppRowSurface(
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: AppSize.cta + 4),
        child: Row(
          children: [
            Expanded(
              // The toggle is one node beside the pencil, which a screen
              // reader reaches on its own.
              child: Semantics(
                container: true,
                button: true,
                label: shown
                    ? l10n.cardBackShown(spokenFront, spokenBack)
                    : l10n.cardBackHidden(spokenFront),
                onTapHint: shown ? l10n.hideBack : l10n.showBack,
                onTap: onToggle,
                customSemanticsActions: {
                  CustomSemanticsAction(label: l10n.editCard): onEdit,
                },
                excludeSemantics: true,
                child: InkWell(
                  borderRadius: BorderRadius.horizontal(left: radius),
                  onTap: onToggle,
                  onLongPress: onEdit,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(
                      AppSpace.s16,
                      AppSpace.s12,
                      AppSpace.s4,
                      AppSpace.s12,
                    ),
                    child: isWholeCard(front)
                        ? WholeCardView(
                            front,
                            revealed: shown,
                            style: AppType.bodyStrong,
                          )
                        : Row(
                            spacing: AppSpace.s12,
                            children: [
                              Expanded(
                                child: Text.rich(
                                  contentSpan(l10n, front),
                                  style: AppType.bodyStrong,
                                ),
                              ),
                              if (shown)
                                Expanded(
                                  child: Text.rich(
                                    contentSpan(l10n, back),
                                    textAlign: TextAlign.end,
                                    style: AppType.secondary.copyWith(
                                      color: colors.ink2,
                                    ),
                                  ),
                                )
                              else
                                Container(
                                  width: AppSize.cta * 2 - AppSpace.s16,
                                  height: AppSpace.s24 - 2,
                                  decoration: BoxDecoration(
                                    color: colors.hairline,
                                    borderRadius: BorderRadius.circular(
                                      AppSpace.s8,
                                    ),
                                  ),
                                ),
                            ],
                          ),
                  ),
                ),
              ),
            ),
            IconButton(
              tooltip: l10n.editCard,
              icon: Icon(LucideIcons.pencil, color: colors.ink2),
              onPressed: onEdit,
            ),
          ],
        ),
      ),
    );
  }
}

/// One line of text for a card side: a cloze or a table with its blanks
/// filled, a photo as "사진", a sound as "음성", and a block this version
/// cannot show named by its type.
String describeContent(AppLocalizations l10n, List<Content> blocks) => blocks
    .map(
      (block) => switch (block) {
        TextContent(:final text) => text,
        ClozeContent(:final filled) || TableContent(:final filled) => filled,
        SensesContent(:final lines) => lines,
        ImageContent() => l10n.blockImage,
        AudioContent() => l10n.blockAudio,
        UnsupportedContent(:final type) => l10n.unsupportedContent(type),
      },
    )
    .join(' ');

/// A card side as a screen reader reads it: as [describeContent] has it, but
/// each blank as its answer only when [revealed], else as "빈칸", a table row
/// by row, its cells joined by commas, a span in its cell's text, and the
/// blocks as sentences.
String spokenContent(
  AppLocalizations l10n,
  List<Content> blocks, {
  required bool revealed,
}) {
  String blank(String answer) => revealed ? answer : l10n.blank;
  return blocks
      .map(
        (block) => switch (block) {
          ClozeContent(:final text, :final answers) => [
            for (final (index, part) in text.split(clozeBlank).indexed) ...[
              part,
              if (index < answers.length) blank(answers[index]),
            ],
          ].join(),
          TableContent(:final columns, :final rows) => [
            columns.join(', '),
            for (final (row, cells) in rows.indexed)
              [
                for (final (column, _) in cells.indexed)
                  [
                    for (final run in block.cellRuns(row, column))
                      run.blank ? blank(run.text) : run.text,
                  ].join(),
              ].join(', '),
          ].join('. '),
          // A photo, then each box as a blank, or its answer once revealed.
          ImageContent(:final boxes) => [
            l10n.blockImage,
            for (final box in boxes)
              switch (box.answer) {
                final answer? when answer.trim().isNotEmpty => blank(answer),
                _ => l10n.blank,
              },
          ].join(', '),
          _ => describeContent(l10n, [block]),
        },
      )
      .join('. ');
}
