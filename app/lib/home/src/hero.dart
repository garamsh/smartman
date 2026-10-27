import 'package:flutter/material.dart';

import '../../design/theme.dart';

/// A count on a white hero card: the number large in ink, then [unit] right
/// after it, smaller and muted, read as [semantics].
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
            TextSpan(
              text: unit,
              style: AppType.headline.copyWith(color: colors.muted),
            ),
          ],
        ),
        style: TextStyle(color: colors.ink),
      ),
    );
  }
}
