import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' hide Card;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../deck/deck.dart' show DeckFailure, DeckSelection, describeFailure;
import '../../l10n/app_localizations.dart';
import 'failure.dart';
import 'failure_message.dart';
import 'overview.dart';
import 'providers.dart';
import 'queue.dart';
import 'today_counter.dart';

/// What a selection holds for today, as the home screen shows it.
sealed class TodayOverviewRead {
  const TodayOverviewRead();
}

/// The overview is being read.
final class OverviewPending extends TodayOverviewRead {
  const OverviewPending();
}

/// The overview could not be read; [message] says why, for the user.
final class OverviewUnavailable extends TodayOverviewRead {
  const OverviewUnavailable(this.message);

  final String message;
}

/// Today's [count], the daily [goal], the [streak] of study days, the
/// [forecast] of the cards due on each of the next [forecastDays] study days,
/// which start at [days], the [dailyMinutes] the user studies a day, and the
/// [extra] cards studied past the day's plan.
final class TodayOverview extends TodayOverviewRead {
  const TodayOverview({
    required this.count,
    required this.goal,
    required this.streak,
    required this.forecast,
    required this.days,
    required this.load,
    required this.dailyMinutes,
    required this.extra,
  });

  final TodayCounted count;
  final DailyGoal goal;
  final int streak;
  final List<int> forecast;

  /// The calendar date each day of [forecast] starts on, at midnight UTC.
  final List<DateTime> days;

  /// The reviews an average day asks for at the cards' current intervals,
  /// rounded up, at least one: the pace a backlog's catch-up is projected at.
  final int load;

  /// The daily study minutes the day takes: the user's, or the default.
  final int dailyMinutes;

  /// How many cards were studied today past the day's plan, never in [goal].
  final int extra;

  /// In a backlog, the overdue reviews left at the start of each day of
  /// [forecast] when the user clears [load] of them a day ([catchUp]).
  List<int> get backlogLeft => catchUp(count.total, load);

  /// The first later day with a card due: how many days after today, and how
  /// many cards; null when none of the forecast's days has one.
  ({int after, int cards})? get nextReview {
    for (var day = 1; day < forecast.length; day++) {
      if (forecast[day] > 0) return (after: day, cards: forecast[day]);
    }
    return null;
  }

  /// The whole minutes [cards] reviews take at the user's pace, rounded up.
  int minutesFor(int cards) => count.pace.minutes(reviews: cards, fresh: 0);
}

/// Builds what the caller shows of a [TodayOverviewRead].
typedef TodayOverviewBuilder = Widget Function(
  BuildContext context,
  TodayOverviewRead overview,
);

/// Reads [decks]' [TodayOverview]: [TodayCounter]'s count, the daily goal
/// from the answers recorded today, the streak as the completion card counts
/// it, and the forecast; shows it through [builder].
///
/// It is read again when [decks] changes and whenever the route that shows it
/// comes back on top.
class TodayOverviewReader extends ConsumerStatefulWidget {
  const TodayOverviewReader({
    super.key,
    required this.decks,
    required this.builder,
  });

  final DeckSelection decks;
  final TodayOverviewBuilder builder;

  @override
  ConsumerState<TodayOverviewReader> createState() =>
      _TodayOverviewReaderState();
}

class _TodayOverviewReaderState extends ConsumerState<TodayOverviewReader> {
  late Future<TodayOverview> _overview = _read();
  bool _onTop = true;

  Future<TodayOverview> _read() async {
    final today = await readToday(widget.decks, ref);
    final repository = ref.read(studyRepositoryProvider);
    final now = ref.read(studyClockProvider)();
    final zone = ref.read(studyZoneProvider);
    final start = today.day.start;
    final answers = await repository.answersSince(start);
    final days = <DateTime>[start];
    while (days.length < forecastDays) {
      days.add(studyDayEnd(days.last, zone));
    }
    return TodayOverview(
      count: today.count,
      goal: DailyGoal.of(today.plan),
      streak: streak(
        [for (final answer in answers) answer.at],
        now,
        since: start,
        daysBefore: await studyDaysBefore(
          start,
          repository.latestAnswerBefore,
          zone,
        ),
        offsetAt: zone,
      ),
      forecast: forecast(
        today.states.values,
        today.day,
        load: today.count.total,
        offsetAt: zone,
      ),
      load: max(1, dailyLoad(today.states.values).ceil()),
      dailyMinutes: today.dailyMinutes,
      extra: today.plan.extra.length,
      days: [
        for (final day in days)
          if (day.toUtc().add(zone(day)) case final wall)
            DateTime.utc(wall.year, wall.month, wall.day),
      ],
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final onTop = ModalRoute.isCurrentOf(context) ?? true;
    if (onTop && !_onTop) _overview = _read();
    _onTop = onTop;
  }

  @override
  void didUpdateWidget(TodayOverviewReader oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!setEquals(oldWidget.decks.ids, widget.decks.ids)) _overview = _read();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return FutureBuilder(
      future: _overview,
      builder: (context, read) => widget.builder(context, switch (read) {
        AsyncSnapshot(hasError: true, :final error?) => OverviewUnavailable(
          switch (error) {
            DeckFailure() => describeFailure(l10n, error),
            StudyFailure() => describeStudyFailure(l10n, error),
            _ => Error.throwWithStackTrace(
              error,
              read.stackTrace ?? StackTrace.empty,
            ),
          },
        ),
        AsyncSnapshot<TodayOverview>(:final data?) => data,
        _ => const OverviewPending(),
      }),
    );
  }
}
