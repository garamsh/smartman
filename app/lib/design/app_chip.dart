import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import 'theme.dart';

/// How a status chip is coloured.
enum AppChipTone {
  /// The surface inside an outline, with ink text.
  neutral,

  /// The brand tint, for what is due today.
  brand,
}

/// What a chip is: a label, a button, or a choice that is on or off.
sealed class AppChipKind {
  const AppChipKind();
}

/// A label that states something, in its [tone]; not a button.
final class AppChipStatus extends AppChipKind {
  const AppChipStatus({this.tone = AppChipTone.neutral});

  final AppChipTone tone;
}

/// A button on the surface inside an outline; [icon] trails its label.
final class AppChipAction extends AppChipKind {
  const AppChipAction({required this.onPressed, this.icon});

  final VoidCallback onPressed;
  final IconData? icon;
}

/// A choice: on, the navy fill, inverted in the dark theme, with a check;
/// off, the surface inside an outline. A screen reader hears it as selected
/// or not.
final class AppChipChoice extends AppChipKind {
  const AppChipChoice({required this.selected, required this.onPressed});

  final bool selected;
  final VoidCallback onPressed;
}

/// A small, fully rounded chip of one [kind]. A button or a choice has a tap
/// area of at least the minimum target.
class AppChip extends StatelessWidget {
  const AppChip({
    super.key,
    required this.label,
    this.kind = const AppChipStatus(),
  });

  final String label;
  final AppChipKind kind;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final (fill, onFill, outline) = switch (kind) {
      AppChipStatus(tone: AppChipTone.brand) => (
        colors.brandTint,
        colors.ink,
        colors.brandTint,
      ),
      AppChipChoice(selected: true) => (
        colors.ink,
        colors.onPrimary,
        colors.ink,
      ),
      AppChipStatus(tone: AppChipTone.neutral) ||
      AppChipAction() ||
      AppChipChoice(
        selected: false,
      ) => (colors.surface, colors.ink, colors.outline),
    };
    final shape = StadiumBorder(side: BorderSide(color: outline));
    final style = AppType.micro.copyWith(
      color: onFill,
      fontWeight: FontWeight.w600,
    );
    Widget button(VoidCallback onPressed, IconData? icon) => TextButton(
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
    return switch (kind) {
      AppChipStatus() => DecoratedBox(
        decoration: ShapeDecoration(color: fill, shape: shape),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpace.s12,
            vertical: AppSpace.s4,
          ),
          child: Text(label, style: style),
        ),
      ),
      AppChipAction(:final onPressed, :final icon) => button(onPressed, icon),
      AppChipChoice(:final selected, :final onPressed) => MergeSemantics(
        child: Semantics(
          selected: selected,
          child: button(onPressed, selected ? LucideIcons.check : null),
        ),
      ),
    };
  }
}
