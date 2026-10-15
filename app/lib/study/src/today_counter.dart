import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../deck/deck.dart'
    show
        DeckFailure,
        DeckSelection,
        TodayBuilder,
        TodayCount,
        TodayCounted,
        TodayPending,
        TodayUnavailable,
        deckRepositoryProvider,
        describeFailure;
import '../../shared/l10n/app_localizations.dart';
import 'failure.dart';
import 'failure_message.dart';
import 'providers.dart';
import 'queue.dart';

/// Counts the due and new cards a session over [decks] would study now, by
/// the rules that build its queue, and whether new cards pause for a backlog,
/// and shows the count through [builder].
///
/// The count is read again when [decks] changes and whenever the route that
/// shows it comes back on top.
class TodayCounter extends ConsumerStatefulWidget {
  const TodayCounter({super.key, required this.decks, required this.builder});

  final DeckSelection decks;
  final TodayBuilder builder;

  @override
  ConsumerState<TodayCounter> createState() => _TodayCounterState();
}

class _TodayCounterState extends ConsumerState<TodayCounter> {
  late Future<TodayCounted> _count = _read();
  bool _onTop = true;

  Future<TodayCounted> _read() async {
    final (cards, states) = await readCards(
      widget.decks,
      ref.read(deckRepositoryProvider),
      ref.read(studyRepositoryProvider),
    );
    final queue = selectQueue(cards, states, ref.read(studyClockProvider)());
    if (queue.backlog) return TodayCounted.backlog(review: queue.cards.length);
    final fresh = queue.cards
        .where((card) => !states.containsKey(card.id))
        .length;
    return TodayCounted(review: queue.cards.length - fresh, fresh: fresh);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final onTop = ModalRoute.isCurrentOf(context) ?? true;
    if (onTop && !_onTop) _count = _read();
    _onTop = onTop;
  }

  @override
  void didUpdateWidget(TodayCounter oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!setEquals(oldWidget.decks.ids, widget.decks.ids)) _count = _read();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return FutureBuilder(
      future: _count,
      builder: (context, count) => widget.builder(context, switch (count) {
        AsyncSnapshot(hasError: true, :final error?) => TodayUnavailable(
          _describe(l10n, error, count.stackTrace ?? StackTrace.empty),
        ),
        AsyncSnapshot<TodayCount>(:final data?) => data,
        _ => const TodayPending(),
      }),
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
