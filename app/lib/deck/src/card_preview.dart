import 'package:flutter/material.dart';

import '../../design/theme.dart';
import '../../l10n/app_localizations.dart';
import 'card_list.dart';
import 'card_text.dart';
import 'content.dart';
import 'split_card.dart';
import 'whole_card_view.dart';

/// A card as the study screen shows it with its answer revealed: the question
/// on the left half and the answer on the right, each centred and fitted to
/// its half, or a whole card's front with its blanks filled, on a rounded
/// surface.
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
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(AppRadius.card),
        boxShadow: AppShadow.card(colors),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: minHeight),
        child: isWholeCard(front)
            ? Center(
                child: Padding(
                  padding: const EdgeInsets.all(AppSpace.s16),
                  child: LayoutBuilder(
                    builder: (context, constraints) => WholeCardView(
                      front,
                      revealed: true,
                      style: AppType.question,
                      minFontSize: AppType.questionFloor,
                      width: constraints.maxWidth,
                    ),
                  ),
                ),
              )
            : SplitCard(
                front: (context, width) => CardText(
                  describeContent(l10n, front),
                  style: AppType.question,
                  minFontSize: AppType.questionFloor,
                  width: width,
                ),
                back: (context, width) => CardText(
                  describeContent(l10n, back),
                  style: AppType.answer,
                  minFontSize: AppType.answerFloor,
                  width: width,
                ),
              ),
      ),
    );
  }
}
