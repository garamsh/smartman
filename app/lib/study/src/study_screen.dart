import 'package:flutter/material.dart' hide Card;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../deck/deck.dart';
import '../../shared/l10n/app_localizations.dart';
import '../../shared/theme.dart';
import '../../shared/ui/app_button.dart';
import '../../shared/ui/mascot.dart';
import 'current_card.dart';
import 'failure.dart';
import 'failure_message.dart';
import 'providers.dart';
import 'session.dart';
import 'session_scroll.dart';
import 'study_style.dart';

/// Studies the cards of [decks] left today in one session, one card at a time,
/// answered by swiping, below every card answered so far; then shows the
/// completion card, from which practice goes on in the same screen.
class StudyScreen extends ConsumerStatefulWidget {
  const StudyScreen({super.key, required this.decks});

  final DeckSelection decks;

  @override
  ConsumerState<StudyScreen> createState() => _StudyScreenState();
}

class _StudyScreenState extends ConsumerState<StudyScreen> {
  late final StudySession _session;
  late ScaffoldMessengerState _messenger;
  late AppLocalizations _l10n;

  @override
  void initState() {
    super.initState();
    final clock = ref.read(studyClockProvider);
    _session = StudySession(
      decks: widget.decks,
      cards: ref.read(deckRepositoryProvider),
      repository: ref.read(studyRepositoryProvider),
      scheduler: ref.read(schedulerProvider),
      clock: clock,
      random: ref.read(studyRandomProvider)(clock()),
      onFailure: _report,
      offsetAt: ref.read(studyZoneProvider),
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Kept for writes that fail after this screen has closed.
    _messenger = ScaffoldMessenger.of(context);
    _l10n = AppLocalizations.of(context);
  }

  @override
  void dispose() {
    _session.dispose();
    super.dispose();
  }

  void _report(StudyFailure failure) => _messenger.showSnackBar(
    SnackBar(content: Text(describeStudyFailure(_l10n, failure))),
  );

  @override
  Widget build(BuildContext context) {
    // The current card's centre, measured from the top of the screen, is
    // placed relative to the body below the top bar.
    final screenHeight = MediaQuery.sizeOf(context).height;
    final bodyTop = MediaQuery.paddingOf(context).top + StudyStyle.topBarHeight;
    return ListenableBuilder(
      listenable: _session,
      builder: (context, _) {
        final state = _session.state;
        return Scaffold(
          body: SafeArea(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _TopBar(
                  progress: switch (state) {
                    SessionStudying(:final progress) ||
                    SessionComplete(:final progress) => progress,
                    _ => null,
                  },
                  onClose: () => Navigator.of(context).maybePop(),
                ),
                Expanded(
                  child: _body(
                    context,
                    state,
                    currentCenter:
                        screenHeight * StudyStyle.currentCenterFraction -
                        bodyTop,
                    currentMaxHeight:
                        screenHeight * StudyStyle.currentMaxHeightFraction,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _body(
    BuildContext context,
    SessionState state, {
    required double currentCenter,
    required double currentMaxHeight,
  }) {
    final l10n = AppLocalizations.of(context);
    final (previous, current) = switch (state) {
      SessionLoading() => (
        null,
        const Center(child: CircularProgressIndicator()),
      ),
      CardsUnreadable(:final failure) => (
        null,
        Center(child: Text(describeFailure(l10n, failure))),
      ),
      StatesUnreadable(:final failure) => (
        null,
        Center(child: Text(describeStudyFailure(l10n, failure))),
      ),
      SessionStudying(:final current, :final previous) => (
        previous,
        CurrentCard(
          // A new key for each card shown, a re-shown card included.
          key: ValueKey(('card', previous.length)),
          card: current,
          onAnswer: _session.answer,
        ),
      ),
      SessionEmpty() => (
        null,
        Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpace.s20),
            child: Text(
              l10n.nothingToStudyToday,
              textAlign: TextAlign.center,
              style: AppType.body.copyWith(color: AppColors.of(context).muted),
            ),
          ),
        ),
      ),
      SessionComplete(:final completion, :final previous) => (
        previous,
        _CompletionCard(
          key: const ValueKey('completion'),
          completion: completion,
          onPractice: _session.practice,
        ),
      ),
    };
    if (previous == null) return current;
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    final switcher = AnimatedSwitcher(
      duration: reduceMotion
          ? StudyStyle.fadeDuration
          : StudyStyle.settleDuration,
      switchInCurve: Curves.easeOutCubic,
      transitionBuilder: reduceMotion
          ? AnimatedSwitcher.defaultTransitionBuilder
          : _emerge,
      layoutBuilder: (current, previous) => Stack(
        alignment: Alignment.topCenter,
        children: [...previous, ?current],
      ),
      child: current,
    );
    return SessionScroll(
      cards: previous,
      onToggle: _session.toggle,
      currentCenter: currentCenter,
      // The completion card may grow past a card's cap, up to the space below
      // the top bar, so its actions are not scrolled out of reach.
      currentMaxHeight: state is SessionStudying
          ? currentMaxHeight
          : double.infinity,
      // The hints hang below the card, outside its box, so the card alone is
      // placed as ADR 0023 places it.
      current: state is SessionStudying
          ? Stack(
              clipBehavior: Clip.none,
              children: [
                switcher,
                const Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: FractionalTranslation(
                    translation: Offset(0, 1),
                    child: Padding(
                      padding: EdgeInsets.only(top: StudyStyle.hintGap),
                      child: _SwipeHints(),
                    ),
                  ),
                ),
              ],
            )
          : switcher,
    );
  }
}

/// Under the current card: a left chevron with "모른다" and "안다" with a right
/// chevron, saying which way answers which. A screen reader reaches both
/// answers as the card's actions, so it skips these.
class _SwipeHints extends StatelessWidget {
  const _SwipeHints();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colors = AppColors.of(context);
    final style = AppType.section.copyWith(color: colors.muted);
    return ExcludeSemantics(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppSpace.s4),
        child: Row(
          children: [
            Icon(
              LucideIcons.chevronLeft,
              size: AppSize.smallIcon,
              color: colors.dontKnowText,
            ),
            Text(l10n.swipeDontKnowHint, style: style),
            const Spacer(),
            Text(l10n.swipeKnowHint, style: style),
            Icon(
              LucideIcons.chevronRight,
              size: AppSize.smallIcon,
              color: colors.know,
            ),
          ],
        ),
      ),
    );
  }
}

/// Brings the next card up from slightly below and smaller.
Widget _emerge(Widget child, Animation<double> animation) => AnimatedBuilder(
  animation: animation,
  builder: (context, child) => Transform.translate(
    offset: Offset(0, StudyStyle.emergeOffset * (1 - animation.value)),
    child: Transform.scale(
      scale:
          StudyStyle.emergeScale +
          (1 - StudyStyle.emergeScale) * animation.value,
      child: FadeTransition(opacity: animation, child: child),
    ),
  ),
  child: child,
);

/// The close button, the progress bar and the count of cards answered.
class _TopBar extends StatelessWidget {
  const _TopBar({required this.progress, required this.onClose});

  final SessionProgress? progress;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colors = AppColors.of(context);
    final progress = this.progress;
    return Material(
      color: colors.ground,
      child: SizedBox(
        height: StudyStyle.topBarHeight,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpace.s8),
          child: Row(
            spacing: AppSpace.s12,
            children: [
              IconButton(
                tooltip: l10n.close,
                icon: const Icon(LucideIcons.x),
                onPressed: onClose,
              ),
              if (progress != null) ...[
                Expanded(
                  child: LinearProgressIndicator(
                    value: progress.total == 0
                        ? 1
                        : progress.answered / progress.total,
                    minHeight: StudyStyle.progressHeight,
                    color: colors.ink,
                    backgroundColor: colors.hairline,
                    borderRadius: BorderRadius.circular(
                      StudyStyle.progressHeight,
                    ),
                    semanticsLabel: l10n.studyProgressSemantics(
                      progress.answered,
                      progress.total,
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.only(right: AppSpace.s12),
                  child: ExcludeSemantics(
                    child: Text(
                      l10n.studyProgress(progress.answered, progress.total),
                      style: AppType.secondary.copyWith(
                        color: colors.ink,
                        fontWeight: FontWeight.w700,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// The completion card in the current card's place once no card is left
/// today: the mascot, the heading, today's answers, time and streak, and the
/// choice to go on as practice or to stop.
class _CompletionCard extends StatelessWidget {
  const _CompletionCard({
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
          minHeight: StudyStyle.currentMinHeight,
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
                            color: colors.ink2,
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
