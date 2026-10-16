import 'package:flutter/material.dart';

import '../../design/theme.dart';

/// Quiet text on the navy cards: their white, a step back.
Color heroQuiet(AppColors colors) => colors.onHero.withValues(alpha: 0.8);

/// A track on the navy cards, under a bar or a ring: their white, faint.
Color heroTrack(AppColors colors) => colors.onHero.withValues(alpha: 0.16);

/// A count on a navy card: the number large, then [unit] beside it, read as
/// [semantics].
class HeroCount extends StatelessWidget {
  const HeroCount({
    super.key,
    required this.count,
    required this.unit,
    required this.semantics,
  });

  final int count;
  final String unit;
  final String semantics;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return Semantics(
      container: true,
      label: semantics,
      excludeSemantics: true,
      child: Text.rich(
        TextSpan(
          children: [
            TextSpan(text: '$count', style: AppType.figure),
            const TextSpan(text: ' '),
            TextSpan(
              text: unit,
              style: AppType.headline.copyWith(color: heroQuiet(colors)),
            ),
          ],
        ),
        style: TextStyle(color: colors.onHero),
      ),
    );
  }
}
