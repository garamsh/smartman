import 'package:flutter/material.dart';

import '../theme.dart';

/// A row of a list: a rounded surface on the ground, tappable when [onTap] or
/// [onLongPress] is given, with the row gap below it. [child] fills it.
class AppRowSurface extends StatelessWidget {
  const AppRowSurface({
    super.key,
    required this.child,
    this.onTap,
    this.onLongPress,
    this.onSheet = false,
  });

  final Widget child;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  /// Whether the row sits on a sheet, where it takes the ground colour to
  /// stand apart from the sheet's surface.
  final bool onSheet;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(AppRadius.row);
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpace.rowGap),
      child: Material(
        color: onSheet
            ? AppColors.of(context).ground
            : AppColors.of(context).surface,
        borderRadius: radius,
        child: onTap == null && onLongPress == null
            ? child
            : InkWell(
                borderRadius: radius,
                onTap: onTap,
                onLongPress: onLongPress,
                child: child,
              ),
      ),
    );
  }
}

/// A row with a [title], an optional [subtitle] under it, and optional
/// [leading] and [trailing] widgets, read as one node.
class AppListRow extends StatelessWidget {
  const AppListRow({
    super.key,
    required this.title,
    this.subtitle,
    this.leading,
    this.trailing,
    this.selected,
    this.onTap,
    this.onLongPress,
    this.onSheet = false,
  });

  final String title;
  final String? subtitle;
  final Widget? leading;
  final Widget? trailing;

  /// Whether the row is selected, or null where rows are not selectable.
  final bool? selected;

  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  /// Whether the row sits on a sheet; see [AppRowSurface.onSheet].
  final bool onSheet;

  @override
  Widget build(BuildContext context) {
    final subtitle = this.subtitle;
    return MergeSemantics(
      child: Semantics(
        selected: selected,
        child: AppRowSurface(
          onTap: onTap,
          onLongPress: onLongPress,
          onSheet: onSheet,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpace.s16,
              AppSpace.s12,
              AppSpace.s12,
              AppSpace.s12,
            ),
            child: Row(
              spacing: AppSpace.s12,
              children: [
                ?leading,
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(title, style: AppType.bodyStrong),
                      if (subtitle != null)
                        Text(
                          subtitle,
                          style: AppType.caption.copyWith(
                            color: AppColors.of(context).muted,
                          ),
                        ),
                    ],
                  ),
                ),
                ?trailing,
              ],
            ),
          ),
        ),
      ),
    );
  }
}
