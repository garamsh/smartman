import 'package:flutter/material.dart' hide Card;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../deck/deck.dart';
import '../../shared/l10n/app_localizations.dart';
import '../../shared/theme.dart';
import '../../shared/ui/app_button.dart';
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
        _Summary(key: const ValueKey('summary'), summary: summary),
      ),
    };
    if (previous == null) return current;
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    return SessionScroll(
      cards: previous,
      onToggle: _session.toggle,
      currentCenter: currentCenter,
      currentMaxHeight: currentMaxHeight,
      current: AnimatedSwitcher(
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
                    color: colors.know,
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
                      style: AppType.caption.copyWith(
                        color: colors.muted,
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

/// The finished session's counts, in the current card's place.
class _Summary extends StatelessWidget {
  const _Summary({super.key, required this.summary});

  final SessionSummary summary;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colors = AppColors.of(context);
    final time = summary.timeSpent;
    final muted = AppType.secondary.copyWith(color: colors.muted);
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
              Semantics(
                header: true,
                child: Text(l10n.sessionSummaryTitle, style: AppType.title),
              ),
              const SizedBox(height: AppSpace.s4),
              if (summary.cardsStudied == 0)
                Text(l10n.nothingToStudy, style: muted),
              Text(l10n.cardsStudied(summary.cardsStudied), style: muted),
              Text(
                l10n.timeSpent(time.inMinutes, time.inSeconds.remainder(60)),
                style: muted,
              ),
              const SizedBox(height: AppSpace.s16),
              Row(
                spacing: AppSpace.s8,
                children: [
                  Expanded(
                    child: _Tally(
                      text: l10n.knowCount(summary.knowCount),
                      dot: colors.knowDot,
                    ),
                  ),
                  Expanded(
                    child: _Tally(
                      text: l10n.dontKnowCount(summary.dontKnowCount),
                      dot: colors.dontKnow,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpace.s20),
              AppButton(
                label: l10n.done,
                onPressed: () => Navigator.of(context).pop(),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// One answer's count on the ground, after its dot.
class _Tally extends StatelessWidget {
  const _Tally({required this.text, required this.dot});

  final String text;
  final Color dot;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.ground,
        borderRadius: BorderRadius.circular(AppRadius.row),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpace.s12,
          vertical: AppSpace.s12,
        ),
        child: Row(
          spacing: AppSpace.s8,
          children: [
            Container(
              width: StudyStyle.dotSize,
              height: StudyStyle.dotSize,
              decoration: BoxDecoration(color: dot, shape: BoxShape.circle),
            ),
            Expanded(child: Text(text, style: AppType.bodyStrong)),
          ],
        ),
      ),
    );
  }
}
