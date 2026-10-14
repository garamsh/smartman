import 'package:flutter/material.dart';

import '../../shared/theme.dart';

/// A card as the study screen shows it with its answer revealed: the question
/// on the left half and the answer on the right, on a rounded surface.
class CardPreview extends StatelessWidget {
  const CardPreview({super.key, required this.front, required this.back});

  final String front;
  final String back;

  /// The preview's height before its text grows it.
  static const minHeight = 160.0;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final style = Theme.of(context).textTheme.titleLarge;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(AppRadius.card),
        boxShadow: [
          BoxShadow(
            color: colors.shadow.withValues(alpha: 0.12),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: minHeight),
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(child: _Half(front, style: style)),
              const VerticalDivider(width: 1),
              Expanded(child: _Half(back, style: style)),
            ],
          ),
        ),
      ),
    );
  }
}

class _Half extends StatelessWidget {
  const _Half(this.text, {required this.style});

  final String text;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(16),
    child: SizedBox(
      width: double.infinity,
      child: Text(text, style: style),
    ),
  );
}
