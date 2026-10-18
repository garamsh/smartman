import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../l10n/app_localizations.dart';
import '../../design/app_button.dart';
import '../../design/theme.dart';

/// One cycle of a coach's demonstration: the card moves out, holds, and
/// springs back.
const coachCycle = Duration(milliseconds: 2800);

/// How far, from 0 to 1, a coach's demonstrated card is out at [t], the
/// progress through one [coachCycle]: out with an ease from a fifth of the
/// way, held, and back with a spring from three fifths.
double coachPeek(double t) {
  final out = Curves.easeOutCubic.transform(((t - 0.2) / 0.26).clamp(0, 1));
  final back = Curves.easeOutBack.transform(((t - 0.62) / 0.18).clamp(0, 1));
  return out - back;
}

/// Whether a coach's finger shows at [t], the progress through one
/// [coachCycle]: from just before the card moves until just after it is
/// back.
bool coachFingerShown(double t) => t > 0.08 && t < 0.68;

/// A coach's finger over the card it demonstrates on, hidden from screen
/// readers, which read the coach's caption instead.
class StudyCoachFinger extends StatelessWidget {
  const StudyCoachFinger({super.key, required this.shown});

  final bool shown;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return IgnorePointer(
      child: ExcludeSemantics(
        child: Opacity(
          opacity: shown ? 1 : 0,
          child: Icon(
            LucideIcons.pointer,
            size: AppSize.coachFinger,
            color: colors.ink,
            shadows: [
              Shadow(color: colors.shadow, blurRadius: AppSize.coachFingerBlur),
            ],
          ),
        ),
      ),
    );
  }
}

/// A first-use coach's caption on the navy surface, in the place of the
/// screen's main action: the step's [line], a dot for each of [steps] with
/// [step] (from 0) drawn long, "건너뛰기" and "다음", the last step's
/// "시작하기". A screen reader hears the step of how many as it changes.
class StudyCoach extends StatelessWidget {
  const StudyCoach({
    super.key,
    required this.line,
    required this.step,
    required this.steps,
    required this.onNext,
    required this.onSkip,
  });

  final String line;
  final int step;
  final int steps;
  final VoidCallback onNext;
  final VoidCallback onSkip;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colors = AppColors.of(context);
    return Semantics(
      container: true,
      liveRegion: true,
      label: l10n.coachStep(step + 1, steps),
      child: Container(
        padding: const EdgeInsets.fromLTRB(
          AppSpace.s20,
          AppSpace.s16,
          AppSpace.s16,
          AppSpace.s12,
        ),
        decoration: BoxDecoration(
          color: colors.hero,
          borderRadius: BorderRadius.circular(AppRadius.card),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    line,
                    style: AppType.bodyStrong.copyWith(color: colors.onHero),
                  ),
                ),
                for (var dot = 0; dot < steps; dot++)
                  Container(
                    width: dot == step
                        ? AppSize.coachDotCurrent
                        : AppSize.coachDot,
                    height: AppSize.coachDot,
                    margin: const EdgeInsets.only(left: AppSpace.s4),
                    decoration: BoxDecoration(
                      color: colors.onHero.withValues(
                        alpha: dot == step ? 1 : 0.4,
                      ),
                      borderRadius: BorderRadius.circular(AppSize.coachDot / 2),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: AppSpace.s8),
            Row(
              children: [
                AppButton(
                  label: l10n.coachSkip,
                  variant: AppButtonVariant.onHeroText,
                  onPressed: onSkip,
                ),
                const Spacer(),
                AppButton(
                  label: step == steps - 1 ? l10n.coachStart : l10n.coachNext,
                  variant: AppButtonVariant.onHero,
                  onPressed: onNext,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
