import 'package:flutter/material.dart';

import '../../shared/theme.dart';
import '../../shared/ui/card_text.dart';
import 'split_card.dart';

/// A card as the study screen shows it with its answer revealed: the question
/// on the left half and the answer on the right, each centred and fitted to
/// its half, on a rounded surface.
class CardPreview extends StatelessWidget {
  const CardPreview({super.key, required this.front, required this.back});

  final String front;
  final String back;

  /// The preview's height before its text grows it.
  static const minHeight = 160.0;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(AppRadius.card),
        boxShadow: AppShadow.card(colors),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: minHeight),
        child: SplitCard(
          front: (context, width) => CardText(
            front,
            style: AppType.question,
            minFontSize: AppType.questionFloor,
            width: width,
          ),
          back: (context, width) => CardText(
            back,
            style: AppType.answer,
            minFontSize: AppType.answerFloor,
            width: width,
          ),
        ),
      ),
    );
  }
}
