import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../design/app_button.dart';
import '../../design/mascot.dart';
import '../../design/theme.dart';
import '../../l10n/app_localizations.dart';
import 'session.dart';
import 'study_style.dart';

/// The completion card in the current card's place once no card is left
/// today: the mascot, the heading, today's answers, time and streak, and the
/// choice to go on as practice or to stop.
class CompletionCard extends StatelessWidget {
  const CompletionCard({
    super.key,
    required this.completion,
    required this.onPractice,
  });

  final Completion completion;
  final VoidCallback onPractice;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colors = AppColors.of(context);
    final minutes = (completion.timeSpent.inSeconds / 60).ceil();
    final line = AppType.secondary.copyWith(color: colors.ink2);
    TextSpan count(String value, Color color) => TextSpan(
      text: value,
      style: TextStyle(color: color, fontWeight: FontWeight.w700),
    );
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(StudyStyle.cardRadius),
        boxShadow: AppShadow.raised(colors),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(
          minHeight: StudyStyle.completionMinHeight,
        ),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(
            AppSpace.s20,
            AppSpace.s28,
            AppSpace.s20,
            AppSpace.s20,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            spacing: AppSpace.s12,
            children: [
              Center(
                child: Mascot(
                  size: AppSize.mascotMedium,
                  fill: colors.brandTint,
                ),
              ),
              Semantics(
                header: true,
                child: Text(
                  l10n.studyComplete,
                  textAlign: TextAlign.center,
                  style: AppType.title,
                ),
              ),
              Semantics(
                label: l10n.completionSemantics(
                  completion.knowCount,
                  completion.dontKnowCount,
                  minutes,
                  completion.streak,
                ),
                child: ExcludeSemantics(
                  child: Wrap(
                    alignment: WrapAlignment.center,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    spacing: AppSpace.s16,
                    runSpacing: AppSpace.s4,
                    children: [
                      Text.rich(
                        TextSpan(
                          children: [
                            count('${completion.knowCount}', colors.know),
                            TextSpan(text: ' ${l10n.know}'),
                          ],
                        ),
                        style: line,
                      ),
                      Text.rich(
                        TextSpan(
                          children: [
                            count(
                              '${completion.dontKnowCount}',
                              colors.dontKnowText,
                            ),
                            TextSpan(text: ' ${l10n.dontKnow}'),
                          ],
                        ),
                        style: line,
                      ),
                      Text.rich(
                        count(l10n.completionMinutes(minutes), colors.ink),
                        style: line,
                      ),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        spacing: AppSpace.s4,
                        children: [
                          Icon(
                            LucideIcons.flame,
                            size: AppSize.smallIcon,
                            color: colors.streak,
                          ),
                          Text.rich(
                            count(
                              l10n.completionStreak(completion.streak),
                              colors.ink,
                            ),
                            style: line,
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: AppSpace.s4),
              AppButton(
                label: l10n.keepStudying,
                size: AppButtonSize.cta,
                onPressed: onPractice,
              ),
              AppButton(
                label: l10n.stopStudying,
                variant: AppButtonVariant.text,
                onPressed: () => Navigator.of(context).pop(),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
