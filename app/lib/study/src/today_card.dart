import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../deck/deck.dart'
    show DeckFailure, DeckSelection, deckRepositoryProvider, describeFailure;
import '../../shared/l10n/app_localizations.dart';
import 'failure.dart';
import 'failure_message.dart';
import 'providers.dart';
import 'queue.dart';
import 'study_screen.dart';

/// How many cards a session over [decks] would study now, counted by the
/// rules that build its queue, and the action that starts that session.
///
/// The count is read again when [decks] changes and whenever the route that
/// shows this card comes back on top.
class TodayCard extends ConsumerStatefulWidget {
  const TodayCard({super.key, required this.decks});

  final DeckSelection decks;

  @override
  ConsumerState<TodayCard> createState() => _TodayCardState();
}

class _TodayCardState extends ConsumerState<TodayCard> {
  late Future<int> _count = _read();
  bool _onTop = true;

  Future<int> _read() async {
    final (cards, states) = await readCards(
      widget.decks,
      ref.read(deckRepositoryProvider),
      ref.read(studyRepositoryProvider),
    );
    return selectQueue(cards, states, ref.read(studyClockProvider)()).length;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final onTop = ModalRoute.isCurrentOf(context) ?? true;
    if (onTop && !_onTop) _count = _read();
    _onTop = onTop;
  }

  @override
  void didUpdateWidget(TodayCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!setEquals(oldWidget.decks.ids, widget.decks.ids)) _count = _read();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final textTheme = Theme.of(context).textTheme;
    return Card(
      margin: const EdgeInsets.all(16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          spacing: 16,
          children: [
            Expanded(
              child: FutureBuilder(
                future: _count,
                builder: (context, count) => Text(switch (count) {
                  AsyncSnapshot(hasError: true, :final error?) => _describe(
                    l10n,
                    error,
                    count.stackTrace ?? StackTrace.empty,
                  ),
                  AsyncSnapshot(:final data?) => l10n.todayCards(data),
                  _ => '',
                }, style: textTheme.titleMedium),
              ),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => StudyScreen(decks: widget.decks),
                ),
              ),
              child: Text(l10n.studyAll),
            ),
          ],
        ),
      ),
    );
  }
}

/// The message for a failed count; any error other than a domain failure is
/// rethrown, since no user message can explain it.
String _describe(AppLocalizations l10n, Object error, StackTrace stackTrace) =>
    switch (error) {
      DeckFailure() => describeFailure(l10n, error),
      StudyFailure() => describeStudyFailure(l10n, error),
      _ => Error.throwWithStackTrace(error, stackTrace),
    };
