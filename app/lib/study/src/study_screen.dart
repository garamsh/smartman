import 'package:flutter/material.dart' hide Card;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../deck/deck.dart';
import '../../design/theme.dart';
import '../../l10n/app_localizations.dart';
import 'completion_card.dart';
import 'current_card.dart';
import 'failure.dart';
import 'failure_message.dart';
import 'first_run_guide.dart';
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
        CompletionCard(
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
    final scroll = SessionScroll(
      cards: previous,
      onRedecide: _session.redecide,
      currentCenter: currentCenter,
      // The completion card may grow past a card's cap, up to the space below
      // the top bar, so its actions are not scrolled out of reach.
      currentMaxHeight: state is SessionStudying
          ? currentMaxHeight
          : double.infinity,
      // The answer buttons hang under the card, which alone is placed as ADR
      // 0023 places it.
      footer: state is SessionStudying ? StudyStyle.answerRow : 0,
      current: switcher,
    );
    // The first session's guide takes the space above the card, which no
    // previous card holds yet. The column keeps its key as the guide leaves,
    // so the first answer's transition runs.
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (state is SessionStudying && state.firstRun)
          const Flexible(child: SingleChildScrollView(child: FirstRunGuide())),
        Expanded(key: const ValueKey('session'), child: scroll),
      ],
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
