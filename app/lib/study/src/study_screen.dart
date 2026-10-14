import 'dart:math';

import 'package:flutter/material.dart' hide Card;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../deck/deck.dart';
import '../../shared/l10n/app_localizations.dart';
import 'current_card.dart';
import 'failure.dart';
import 'failure_message.dart';
import 'previous_cards.dart';
import 'providers.dart';
import 'session.dart';
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
    final colors = Theme.of(context).colorScheme;
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
            backgroundColor: colors.surfaceContainer,
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
    return CustomMultiChildLayout(
      delegate: _SessionLayout(
        currentCenter: currentCenter,
        currentMaxHeight: currentMaxHeight,
      ),
      children: [
        LayoutId(
          id: _Region.previous,
          child: PreviousCards(cards: previous, onToggle: _session.toggle),
        ),
        LayoutId(
          id: _Region.current,
          child: AnimatedSwitcher(
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
        ),
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

enum _Region { previous, current }

/// Places the current card with its centre at [currentCenter] while it fits
/// above the bottom, and the previous cards in the space above it.
class _SessionLayout extends MultiChildLayoutDelegate {
  _SessionLayout({required this.currentCenter, required this.currentMaxHeight});

  final double currentCenter;
  final double currentMaxHeight;

  @override
  void performLayout(Size size) {
    final current = layoutChild(
      _Region.current,
      BoxConstraints(
        minWidth: max(0, size.width - StudyStyle.cardMargin * 2),
        maxWidth: max(0, size.width - StudyStyle.cardMargin * 2),
        maxHeight: max(
          0,
          min(currentMaxHeight, size.height - StudyStyle.currentBottomGap),
        ),
      ),
    );
    final top = max(
      0.0,
      min(
        currentCenter - current.height / 2,
        size.height - StudyStyle.currentBottomGap - current.height,
      ),
    );
    positionChild(_Region.current, Offset(StudyStyle.cardMargin, top));
    layoutChild(
      _Region.previous,
      BoxConstraints.tight(
        Size(size.width, max(0, top - StudyStyle.previousGap)),
      ),
    );
    positionChild(_Region.previous, Offset.zero);
  }

  @override
  bool shouldRelayout(_SessionLayout oldDelegate) =>
      currentCenter != oldDelegate.currentCenter ||
      currentMaxHeight != oldDelegate.currentMaxHeight;
}

/// The close button, the progress bar and the count of cards answered.
class _TopBar extends StatelessWidget {
  const _TopBar({required this.progress, required this.onClose});

  final SessionProgress? progress;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final progress = this.progress;
    return Material(
      color: theme.colorScheme.surfaceContainer,
      child: SizedBox(
        height: StudyStyle.topBarHeight,
        child: Row(
          children: [
            IconButton(
              tooltip: l10n.close,
              icon: const Icon(Icons.close),
              onPressed: onClose,
            ),
            if (progress != null) ...[
              Expanded(
                child: LinearProgressIndicator(
                  value: progress.total == 0
                      ? 1
                      : progress.answered / progress.total,
                  minHeight: StudyStyle.progressHeight,
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
                padding: const EdgeInsets.symmetric(
                  horizontal: StudyStyle.cardMargin,
                ),
                child: ExcludeSemantics(
                  child: Text(
                    l10n.studyProgress(progress.answered, progress.total),
                    style: theme.textTheme.labelLarge,
                  ),
                ),
              ),
            ],
          ],
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
    final textTheme = Theme.of(context).textTheme;
    final time = summary.timeSpent;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: StudyStyle.cardColor,
        borderRadius: BorderRadius.circular(StudyStyle.cardRadius),
        boxShadow: StudyStyle.currentShadow,
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(
          minHeight: StudyStyle.currentMinHeight,
        ),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(StudyStyle.cardPadding),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            spacing: StudyStyle.cardPadding / 2,
            children: [
              Text(l10n.sessionSummaryTitle, style: textTheme.headlineSmall),
              if (summary.cardsStudied == 0) Text(l10n.nothingToStudy),
              Text(l10n.cardsStudied(summary.cardsStudied)),
              Text(l10n.knowCount(summary.knowCount)),
              Text(l10n.dontKnowCount(summary.dontKnowCount)),
              Text(
                l10n.timeSpent(time.inMinutes, time.inSeconds.remainder(60)),
              ),
              FilledButton(
                onPressed: () => Navigator.of(context).pop(),
                child: Text(l10n.done),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
