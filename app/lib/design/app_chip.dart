import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import 'theme.dart';

/// How a chip is coloured.
enum AppChipTone {
  /// The surface inside an outline, with ink text.
  neutral,

  /// The brand tint, for what is due today.
  brand,
}

/// A small, fully rounded label. With [onPressed] it is a button whose tap
/// area is at least the minimum target, and [icon] trails its label.
///
/// With [selected] it is a choice that is on or off, whatever its [tone]: on,
/// the navy fill, inverted in the dark theme, with a check; off, outlined.
class AppChip extends StatelessWidget {
  const AppChip({
    super.key,
    required this.label,
    this.tone = AppChipTone.neutral,
    this.icon,
    this.selected,
    this.onPressed,
  }) : assert(selected == null || icon == null, 'a choice draws its own check');

  final String label;
  final AppChipTone tone;
  final IconData? icon;
  final bool? selected;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final selected = this.selected;
    final (fill, onFill, outline) = switch ((selected, tone)) {
      (true, _) => (colors.ink, colors.onPrimary, colors.ink),
      (false, _) || (null, AppChipTone.neutral) => (
        colors.surface,
        colors.ink,
        colors.outline,
      ),
      (null, AppChipTone.brand) => (
        colors.brandTint,
        colors.ink,
        colors.brandTint,
      ),
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
    final icon = selected == true ? LucideIcons.check : this.icon;
    final button = TextButton(
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
    return selected == null
        ? button
        : MergeSemantics(
            child: Semantics(selected: selected, child: button),
          );
  }
}
