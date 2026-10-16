import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../shared/l10n/app_localizations.dart';
import '../../shared/theme.dart';
import '../../shared/ui/mascot.dart';
import 'study_style.dart';

/// Above the first card of the user's first session: the mascot and three
/// lines on how to study, tap to reveal, swipe to answer and pull down for
/// earlier cards.
class FirstRunGuide extends StatelessWidget {
  const FirstRunGuide({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpace.s28,
        AppSpace.s40,
        AppSpace.s28,
        AppSpace.s16,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: AppSpace.s12,
        children: [
          const Center(child: Mascot(size: AppSize.mascotGuide)),
          _Line(icon: LucideIcons.eye, text: l10n.guideReveal),
          _Line(icon: LucideIcons.moveHorizontal, text: l10n.guideSwipe),
          _Line(icon: LucideIcons.arrowDown, text: l10n.guideEarlier),
        ],
      ),
    );
  }
}

/// One line of the guide on its rounded surface, after its icon on a tile.
class _Line extends StatelessWidget {
  const _Line({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(AppRadius.button),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpace.s16,
          vertical: AppSpace.s12,
        ),
        child: Row(
          spacing: AppSpace.s12,
          children: [
            Container(
              width: StudyStyle.guideTile,
              height: StudyStyle.guideTile,
              decoration: BoxDecoration(
                color: colors.brandTint,
                borderRadius: BorderRadius.circular(AppRadius.field),
              ),
              child: Icon(icon, size: AppSize.smallIcon, color: colors.ink),
            ),
            Expanded(
              child: Text(
                text,
                style: AppType.secondary.copyWith(color: colors.ink2),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
