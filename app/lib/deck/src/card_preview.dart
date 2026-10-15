import 'package:flutter/material.dart';

import '../../shared/theme.dart';
import '../../shared/ui/card_text.dart';

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
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      // A half's text width: half the card less the divider and the padding.
      final width = (constraints.maxWidth - 1) / 2 - AppSpace.s16 * 2;
      return _card(context, width);
    },
  );

  Widget _card(BuildContext context, double width) {
    final colors = AppColors.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(AppRadius.card),
        boxShadow: AppShadow.card(colors),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: minHeight),
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: _Half(
                  front,
                  style: AppType.question,
                  minFontSize: AppType.questionFloor,
                  width: width,
                ),
              ),
              const VerticalDivider(width: 1),
              Expanded(
                child: _Half(
                  back,
                  style: AppType.answer,
                  minFontSize: AppType.answerFloor,
                  width: width,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// One side, centred, its text shrunk toward [minFontSize] until its widest
/// word fits [width], as the study card shows it.
class _Half extends StatelessWidget {
  const _Half(
    this.text, {
    required this.style,
    required this.minFontSize,
    required this.width,
  });

  final String text;
  final TextStyle style;
  final double minFontSize;
  final double width;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(AppSpace.s16),
    child: Center(
      child: CardText(
        text,
        style: style,
        minFontSize: minFontSize,
        width: width,
      ),
    ),
  );
}
