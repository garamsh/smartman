import 'package:flutter/material.dart';

import 'theme.dart';

/// How a chip is coloured.
enum AppChipTone {
  /// The surface inside an outline, with ink text.
  neutral,

  /// The brand tint, for what is due today.
  brand,
}

/// A small, fully rounded label that states something, in its [tone].
class AppChip extends StatelessWidget {
  const AppChip({
    super.key,
    required this.label,
    this.tone = AppChipTone.neutral,
  });

  final String label;
  final AppChipTone tone;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final (fill, outline) = switch (tone) {
      AppChipTone.neutral => (colors.surface, colors.outline),
      AppChipTone.brand => (colors.brandTint, colors.brandTint),
    };
    return DecoratedBox(
      decoration: ShapeDecoration(
        color: fill,
        shape: StadiumBorder(side: BorderSide(color: outline)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpace.s12,
          vertical: AppSpace.s4,
        ),
        child: Text(
          label,
          style: AppType.micro.copyWith(
            color: colors.ink,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}
