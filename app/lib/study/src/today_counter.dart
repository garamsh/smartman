import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../deck/deck.dart'
    show DeckFailure, DeckSelection, deckRepositoryProvider, describeFailure;
import '../../l10n/app_localizations.dart';
import 'failure.dart';
import 'failure_message.dart';
import 'providers.dart';
import 'queue.dart';

/// What a session over a selection would study now.
sealed class TodayCount {
  const TodayCount();
}

/// The count is being read.
final class TodayPending extends TodayCount {
  const TodayPending();
}

/// [review] cards are due and [fresh] cards are new, and the user takes
/// [perCard] over one card.
final class TodayCounted extends TodayCount {
  const TodayCounted({
    required this.review,
    required this.fresh,
    this.perCard = defaultPerCard,
  }) : backlog = false;

  /// So many reviews are due that new cards pause until they are done.
  const TodayCounted.backlog({
    required this.review,
    this.perCard = defaultPerCard,
  }) : fresh = 0,
       backlog = true;

  final int review;
  final int fresh;
  final Duration perCard;

  /// The time one card is taken to need while the user's own pace is unknown.
  static const defaultPerCard = Duration(seconds: 10);

  /// Whether new cards pause for a backlog of reviews.
  final bool backlog;

  /// The size of the session: every due card and every new one.
  int get total => review + fresh;

  /// The whole minutes the session takes at [perCard], rounded up.
  int get minutes => (total * perCard.inMilliseconds / 60000).ceil();
}

/// The count could not be read; [message] says why, for the user.
final class TodayUnavailable extends TodayCount {
  const TodayUnavailable(this.message);

  final String message;
}

/// Builds what the caller shows of a [TodayCount].
typedef TodayBuilder = Widget Function(BuildContext context, TodayCount count);

/// Counts the due and new cards left today for a session over [decks], by
/// the rules that build its queue, whether new cards pause for a backlog, and
/// the user's pace, and shows the count through [builder].
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
    final repository = ref.read(studyRepositoryProvider);
    final now = ref.read(studyClockProvider)();
    final zone = ref.read(studyZoneProvider);
    final day = StudyDay.at(
      now,
      firstAnswers: await repository.firstAnswersSince(
        studyDayStart(now, zone),
      ),
      offsetAt: zone,
    );
    final queue = selectQueue(cards, states, day);
    final pace =
        await repository.medianReviewDuration() ?? TodayCounted.defaultPerCard;
    if (queue.backlog) {
      return TodayCounted.backlog(review: queue.cards.length, perCard: pace);
    }
    final fresh = queue.cards
        .where((card) => !states.containsKey(card.id))
        .length;
    return TodayCounted(
      review: queue.cards.length - fresh,
      fresh: fresh,
      perCard: pace,
    );
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
