import 'package:flutter/material.dart' hide Card;
import 'package:flutter/material.dart' as material show Card;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../deck/deck.dart';
import '../../shared/l10n/app_localizations.dart';
import 'failure.dart';
import 'failure_message.dart';
import 'providers.dart';
import 'rust/api/engine.dart';
import 'session.dart';

/// Studies [deck] with the two answer buttons, then shows a summary.
class StudyScreen extends ConsumerStatefulWidget {
  const StudyScreen({super.key, required this.deck});

  final Deck deck;

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
    _session = StudySession(
      deckId: widget.deck.id,
      cards: ref.read(deckRepositoryProvider),
      repository: ref.read(studyRepositoryProvider),
      scheduler: ref.read(schedulerProvider),
      clock: ref.read(studyClockProvider),
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
            appBar: AppBar(title: Text(widget.deck.name)),
            body: SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: _body(context, state),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _body(BuildContext context, SessionState state) {
    final l10n = AppLocalizations.of(context);
    return switch (state) {
      SessionLoading() => const Center(child: CircularProgressIndicator()),
      CardsUnreadable(:final failure) => Center(
        child: Text(describeFailure(l10n, failure)),
      ),
      StatesUnreadable(:final failure) => Center(
        child: Text(describeStudyFailure(l10n, failure)),
      ),
      SessionStudying(:final current, :final previous) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (previous != null) ...[
            _PreviousCardPanel(
              previous: previous,
              onCorrect: _session.correctPrevious,
            ),
            const SizedBox(height: 16),
          ],
          Expanded(
            child: material.Card.outlined(
              child: Center(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(24),
                  child: Text(
                    describeContent(l10n, current.front),
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.headlineMedium,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  style: _answerButtonStyle,
                  onPressed: () => _session.answer(Answer.dontKnow),
                  child: Text(l10n.dontKnow),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: FilledButton(
                  style: _answerButtonStyle,
                  onPressed: () => _session.answer(Answer.know),
                  child: Text(l10n.know),
                ),
              ),
            ],
          ),
        ],
      ),
      SessionFinished(:final summary, :final previous) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (previous != null)
            _PreviousCardPanel(
              previous: previous,
              onCorrect: _session.correctPrevious,
            ),
          Expanded(
            child: Center(child: _Summary(summary: summary)),
          ),
          FilledButton(
            style: _answerButtonStyle,
            onPressed: () => Navigator.of(context).pop(),
            child: Text(l10n.done),
          ),
        ],
      ),
    };
  }
}

final _answerButtonStyle = ButtonStyle(
  minimumSize: WidgetStateProperty.all(const Size.fromHeight(56)),
);

String _answerText(AppLocalizations l10n, Answer answer) => switch (answer) {
  Answer.know => l10n.know,
  Answer.dontKnow => l10n.dontKnow,
};

/// The card answered last, front and back; tapping it corrects a "Know".
class _PreviousCardPanel extends StatelessWidget {
  const _PreviousCardPanel({required this.previous, required this.onCorrect});

  final PreviousCard previous;
  final VoidCallback onCorrect;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final textTheme = Theme.of(context).textTheme;
    final front = describeContent(l10n, previous.card.front);
    final back = describeContent(l10n, previous.card.back);
    final answer = _answerText(l10n, previous.answer);
    final onTap = previous.correctable ? onCorrect : null;
    return Semantics(
      container: true,
      button: previous.correctable,
      label: l10n.previousCardSemantics(front, back, answer),
      onTapHint: previous.correctable ? l10n.correctToDontKnow : null,
      onTap: onTap,
      excludeSemantics: true,
      child: material.Card.filled(
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        l10n.previousCard,
                        style: textTheme.labelMedium,
                      ),
                    ),
                    Text(answer, style: textTheme.labelLarge),
                  ],
                ),
                const SizedBox(height: 8),
                Text(front, style: textTheme.titleMedium),
                Text(back, style: textTheme.bodyLarge),
                if (previous.correctable) ...[
                  const SizedBox(height: 8),
                  Text(l10n.correctToDontKnow, style: textTheme.bodySmall),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Summary extends StatelessWidget {
  const _Summary({required this.summary});

  final SessionSummary summary;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final textTheme = Theme.of(context).textTheme;
    final time = summary.timeSpent;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(l10n.sessionSummaryTitle, style: textTheme.headlineSmall),
        const SizedBox(height: 16),
        if (summary.cardsStudied == 0) Text(l10n.nothingToStudy),
        Text(l10n.cardsStudied(summary.cardsStudied)),
        Text(l10n.knowCount(summary.knowCount)),
        Text(l10n.dontKnowCount(summary.dontKnowCount)),
        Text(l10n.timeSpent(time.inMinutes, time.inSeconds.remainder(60))),
      ],
    );
  }
}
