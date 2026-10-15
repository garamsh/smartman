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

/// Studies the cards of [decks] in one session, one card at a time, answered
/// by swiping, below every card answered so far; then shows a summary.
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
        return PopScope(
          canPop: state is! SessionStudying,
          onPopInvokedWithResult: (didPop, _) {
            if (!didPop) _session.leave();
          },
          child: Scaffold(
            body: SafeArea(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _TopBar(
                    progress: switch (state) {
                      SessionStudying(:final progress) ||
                      SessionFinished(:final progress) => progress,
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
      SessionFinished(:final summary, :final previous) => (
        previous,
        _Summary(
          key: const ValueKey('summary'),
          summary: summary,
          now: ref.read(studyClockProvider)(),
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
      // The summary may grow past a card's cap, up to the space below the
      // top bar, so its action is not scrolled out of reach.
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

/// The finished session in the current card's place: the mascot, when the
/// next review is, the session's counts, its time, and the way back.
class _Summary extends StatelessWidget {
  const _Summary({super.key, required this.summary, required this.now});

  final SessionSummary summary;

  /// The time the summary is shown at, from which the next review is told.
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colors = AppColors.of(context);
    final time = summary.timeSpent;
    final muted = AppType.secondary.copyWith(color: colors.muted);
    final next = summary.nextReview;
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
          padding: const EdgeInsets.all(AppSpace.s24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Mascot(
                  size: AppSize.mascotMedium,
                  fill: colors.brandTint,
                ),
              ),
              const SizedBox(height: AppSpace.s16),
              Semantics(
                header: true,
                child: Text(
                  l10n.sessionSummaryTitle,
                  textAlign: TextAlign.center,
                  style: AppType.title,
                ),
              ),
              const SizedBox(height: AppSpace.s8),
              if (summary.cardsStudied == 0)
                Text(
                  l10n.nothingToStudy,
                  textAlign: TextAlign.center,
                  style: muted,
                )
              else if (next != null)
                Text(
                  _nextReview(l10n, next),
                  textAlign: TextAlign.center,
                  style: muted,
                ),
              const SizedBox(height: AppSpace.s24),
              Row(
                spacing: AppSpace.s8,
                children: [
                  Expanded(
                    child: _Tile(
                      count: summary.cardsStudied,
                      label: l10n.summaryStudied,
                      color: colors.ink,
                    ),
                  ),
                  Expanded(
                    child: _Tile(
                      count: summary.knowCount,
                      label: l10n.know,
                      color: colors.know,
                    ),
                  ),
                  Expanded(
                    child: _Tile(
                      count: summary.dontKnowCount,
                      label: l10n.dontKnow,
                      color: colors.dontKnowText,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpace.s8),
              MergeSemantics(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: colors.ground,
                    borderRadius: BorderRadius.circular(AppRadius.row),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(AppSpace.s16),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(l10n.timeSpentLabel, style: muted),
                        ),
                        Text(
                          l10n.timeSpentValue(
                            time.inMinutes,
                            time.inSeconds.remainder(60),
                          ),
                          style: AppType.bodyStrong,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(height: AppSpace.s24),
              AppButton(
                label: l10n.backToDecks,
                size: AppButtonSize.cta,
                onPressed: () => Navigator.of(context).pop(),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// When [next] is, told by calendar day from [now]: today, tomorrow, or in
  /// so many days.
  String _nextReview(AppLocalizations l10n, DateTime next) {
    final days = DateUtils.dateOnly(next.toLocal())
        .difference(DateUtils.dateOnly(now.toLocal()))
        .inDays;
    return switch (days) {
      <= 0 => l10n.nextReviewToday,
      1 => l10n.nextReviewTomorrow,
      _ => l10n.nextReviewInDays(days),
    };
  }
}

/// One count of the summary over its label, on the ground; the count in the
/// colour of what it counts.
class _Tile extends StatelessWidget {
  const _Tile({required this.count, required this.label, required this.color});

  final int count;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return MergeSemantics(
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: colors.ground,
          borderRadius: BorderRadius.circular(AppRadius.row),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpace.s8,
            vertical: AppSpace.s16,
          ),
          child: Column(
            spacing: AppSpace.s4,
            children: [
              Text('$count', style: AppType.title.copyWith(color: color)),
              Text(
                label,
                textAlign: TextAlign.center,
                style: AppType.caption.copyWith(color: colors.muted),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
