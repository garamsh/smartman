import 'package:flutter/material.dart';

import '../../design/theme.dart';
import '../../l10n/app_localizations.dart';
import '../../study/study.dart';

/// A deck's cards on one rounded bar: the mastered ones in [ink], the
/// learning ones in a quieter shade of it, and the new ones as the track,
/// read as its three counts.
///
/// [ink] and [track] default to the ink and the hairline; on the today card's
/// navy they are its white and its faint white.
class ProgressBar extends StatelessWidget {
  const ProgressBar({
    super.key,
    required this.progress,
    this.height = AppSpace.s8 - 2,
    this.ink,
    this.track,
  });

  final DeckProgress progress;
  final double height;
  final Color? ink;
  final Color? track;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final ink = this.ink ?? colors.ink;
    final total = progress.total;
    return Semantics(
      container: true,
      label: AppLocalizations.of(
        context,
      ).progressSemantics(progress.mastered, progress.learning, progress.fresh),
      excludeSemantics: true,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(height),
        child: SizedBox(
          height: height,
          child: ColoredBox(
            color: track ?? colors.hairline,
            child: total == 0
                ? const SizedBox.expand()
                : Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (progress.mastered > 0)
                        Expanded(
                          flex: progress.mastered,
                          child: ColoredBox(color: ink),
                        ),
                      if (progress.learning > 0)
                        Expanded(
                          flex: progress.learning,
                          child: ColoredBox(color: ink.withValues(alpha: 0.45)),
                        ),
                      if (progress.fresh > 0) Spacer(flex: progress.fresh),
                    ],
                  ),
          ),
        ),
      ),
    );
  }
}
