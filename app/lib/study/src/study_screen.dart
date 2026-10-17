import 'dart:math';

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
import 'previous_card.dart';
import 'study_style.dart';

/// Studies the cards of [decks] left today in one session, one card at a time,
/// answered by swiping, below the card answered just before it; then shows the
/// completion card, from which practice goes on in the same screen.
class StudyScreen extends ConsumerStatefulWidget {
  const StudyScreen({super.key, required this.decks});

  final DeckSelection decks;

  @override
  ConsumerState<StudyScreen> createState() => _StudyScreenState();
}

class _StudyScreenState extends ConsumerState<StudyScreen> {
  late final StudySession _session;
  late final AppLifecycleListener _lifecycle;
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
    // An answer counts only the time the app is resumed.
    _lifecycle = AppLifecycleListener(
      onStateChange: (state) => state == AppLifecycleState.resumed
          ? _session.resume()
          : _session.pause(),
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
    _lifecycle.dispose();
    _session.dispose();
    super.dispose();
  }

  void _report(StudyFailure failure) => _messenger.showSnackBar(
    SnackBar(content: Text(describeStudyFailure(_l10n, failure))),
  );

  @override
  Widget build(BuildContext context) {
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
                Expanded(child: _body(context, state)),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _body(BuildContext context, SessionState state) {
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
        Align(
          key: const ValueKey('completion'),
          alignment: Alignment.topCenter,
          child: CompletionCard(
            completion: completion,
            onPractice: _session.practice,
          ),
        ),
      ),
    };
    if (previous == null) return current;
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    Widget switcher(
      Widget? child,
      AnimatedSwitcherTransitionBuilder transition,
    ) => AnimatedSwitcher(
      duration: reduceMotion
          ? StudyStyle.fadeDuration
          : StudyStyle.settleDuration,
      switchInCurve: Curves.easeOutCubic,
      transitionBuilder: reduceMotion
          ? AnimatedSwitcher.defaultTransitionBuilder
          : transition,
      layoutBuilder: (current, previous) =>
          Stack(fit: StackFit.expand, children: [...previous, ?current]),
      child: child,
    );
    final newest = previous.lastOrNull;
    // The previous card's place holds, before the first answer, the first
    // session's guide.
    final above = newest != null
        ? PreviousCardView(
            // A new key for each answer, so the card answered just now rises
            // in and a change of its answer leaves it in place.
            key: ValueKey(newest.position),
            card: newest,
            onRedecide: (answer) => _session.redecide(newest.position, answer),
          )
        : state is SessionStudying && state.firstRun
        ? const SingleChildScrollView(child: FirstRunGuide())
        : null;
    return LayoutBuilder(
      builder: (context, constraints) {
        // The two cards share the height between the top bar and the answer
        // buttons equally, the completion card's place included, so the
        // previous card keeps its size when the completion card arrives.
        final card = max(
          0.0,
          (constraints.maxHeight -
                  StudyStyle.topGap -
                  StudyStyle.cardGap -
                  StudyStyle.answerRow -
                  StudyStyle.currentBottomGap) /
              2,
        );
        return Padding(
          padding: const EdgeInsets.fromLTRB(
            StudyStyle.cardMargin,
            StudyStyle.topGap,
            StudyStyle.cardMargin,
            StudyStyle.currentBottomGap,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(height: card, child: switcher(above, _rise)),
              const SizedBox(height: StudyStyle.cardGap),
              // The completion card may take the answer buttons' place too,
              // so its actions stay in reach.
              Expanded(child: switcher(current, _emerge)),
            ],
          ),
        );
      },
    );
  }
}

/// Rises the card answered just now into the previous card's place.
Widget _rise(Widget child, Animation<double> animation) => AnimatedBuilder(
  animation: animation,
  builder: (context, child) => Transform.translate(
    offset: Offset(0, StudyStyle.emergeOffset * (1 - animation.value)),
    child: FadeTransition(opacity: animation, child: child),
  ),
  child: child,
);

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
