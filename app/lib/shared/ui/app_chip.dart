import 'package:flutter/material.dart';

import '../theme.dart';

/// How a chip is coloured.
enum AppChipTone {
  /// The surface inside a hairline, with ink text.
  neutral,

  /// "Know" green, for what is due today.
  know,
}

/// A small, fully rounded label. With [onPressed] it is a button whose tap
/// area is at least the minimum target, and [icon] trails its label.
class AppChip extends StatelessWidget {
  const AppChip({
    super.key,
    required this.label,
    this.tone = AppChipTone.neutral,
    this.icon,
    this.onPressed,
  });

  final String label;
  final AppChipTone tone;
  final IconData? icon;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final (fill, onFill, outline) = switch (tone) {
      AppChipTone.neutral => (colors.surface, colors.ink, colors.hairline),
      AppChipTone.know => (colors.know, colors.onKnow, colors.know),
    };
    final shape = StadiumBorder(side: BorderSide(color: outline));
    final style = AppType.micro.copyWith(
      color: onFill,
      fontWeight: FontWeight.w600,
    );
    final onPressed = this.onPressed;
    if (onPressed == null) {
      return DecoratedBox(
        decoration: ShapeDecoration(color: fill, shape: shape),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpace.s12,
            vertical: AppSpace.s4,
          ),
          child: Text(label, style: style),
        ),
      );
    }
    final icon = this.icon;
    return TextButton(
      style: TextButton.styleFrom(
        backgroundColor: fill,
        foregroundColor: onFill,
        textStyle: style,
        shape: shape,
        minimumSize: const Size(AppSize.tapTarget, AppSpace.s32),
        padding: const EdgeInsets.symmetric(horizontal: AppSpace.s12),
        tapTargetSize: MaterialTapTargetSize.padded,
      ),
      onPressed: onPressed,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        spacing: AppSpace.s4,
        children: [
          Flexible(child: Text(label, overflow: TextOverflow.ellipsis)),
          if (icon != null) Icon(icon, size: AppSpace.s16),
        ],
      ),
    );
  }
}
