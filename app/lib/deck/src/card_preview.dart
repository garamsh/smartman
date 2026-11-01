import 'package:flutter/material.dart';

import '../../design/theme.dart';
import '../../design/word_break.dart';
import '../../l10n/app_localizations.dart';
import 'card_list.dart';
import 'card_text.dart';
import 'content.dart';
import 'content_view.dart';
import 'split_card.dart';
import 'whole_card_view.dart';

/// A card as the study screen shows it with its back revealed: the front on
/// the left half and the back on the right, each centred and fitted to its
/// half, its lines broken only between words, or a whole card's 칸 in place,
/// revealed, on a rounded surface.
class CardPreview extends StatelessWidget {
  const CardPreview({super.key, required this.front, required this.back});

  final List<Content> front;
  final List<Content> back;

  /// The preview's height before its text grows it.
  static const minHeight = 160.0;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colors = AppColors.of(context);
    final cells = cellsToDraw(front, back);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(AppRadius.card),
        boxShadow: AppShadow.card(colors),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: minHeight),
        child: isDrawnWhole(cells)
            ? Center(
                child: Padding(
                  padding: const EdgeInsets.all(AppSpace.s16),
                  child: LayoutBuilder(
                    builder: (context, constraints) => WholeCardView.cells(
                      cells,
                      revealed: true,
                      style: AppType.front,
                      minFontSize: AppType.frontFloor,
                      width: constraints.maxWidth,
                    ),
                  ),
                ),
              )
            : SplitCard(
                front: (context, width) => CardText(
                  describeContent(l10n, front),
                  span: contentSpan(l10n, front, wrap: keepWords),
                  style: AppType.front,
                  minFontSize: AppType.frontFloor,
                  width: width,
                ),
                back: (context, width) => CardText(
                  describeContent(l10n, back),
                  span: contentSpan(l10n, back, wrap: keepWords),
                  style: AppType.back,
                  minFontSize: AppType.backFloor,
                  width: width,
                ),
              ),
      ),
    );
  }
}
