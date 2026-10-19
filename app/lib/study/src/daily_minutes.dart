import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../deck/deck.dart' show DeckSelection, deckRepositoryProvider;
import 'providers.dart';
import 'queue.dart';
import 'study_time.dart';
import 'today_counter.dart';

/// What a choice of daily study minutes means for today and the days after,
/// across every deck: the [minutes] the user set, null while none is stored,
/// the reviews [due] as today stood when it started, the cards [started] in
/// it, the [unstarted] cards never answered, the [reviews] left today, at the
/// user's [pace], and whether new cards pause for a [backlog].
final class MinutesPlan {
  const MinutesPlan({
    required this.minutes,
    required this.due,
    required this.started,
    required this.unstarted,
    required this.reviews,
    required this.backlog,
    required this.pace,
    required this.todayStart,
    this.offsetAt = localOffsetAt,
  });

  final int? minutes;
  final int due;
  final int started;
  final int unstarted;
  final int reviews;
  final bool backlog;
  final Pace pace;

  /// When today's study day started.
  final DateTime todayStart;
  final UtcOffsetAt offsetAt;

  /// The minutes a day takes now: the stored ones, or the default.
  int get current => minutes ?? defaultDailyMinutes;

  /// At [minutes] a day: the new cards left today, and the study day on which
  /// the last unstarted card is first answered, null when none is left or
  /// they are never all taken. In a backlog no new card is taken.
  ({int fresh, DateTime? lastDay}) at(int minutes) {
    if (backlog) return (fresh: 0, lastDay: null);
    final perDay = dailyNewCards(minutes: minutes, due: due, pace: pace);
    final fresh = min(unstarted, max(0, perDay - started));
    return (
      fresh: fresh,
      lastDay: unstarted == 0
          ? null
          : lastNewCardDay(
              remaining: unstarted,
              today: fresh,
              perDay: perDay,
              todayStart: todayStart,
              offsetAt: offsetAt,
            ),
    );
  }
}

/// The [MinutesPlan] over every deck, read through [ref].
///
/// A failed read throws the `DeckFailure` or `StudyFailure` that reports it.
Future<MinutesPlan> readMinutesPlan(WidgetRef ref) async {
  final repository = ref.read(studyRepositoryProvider);
  final zone = ref.read(studyZoneProvider);
  final minutes = await repository.dailyMinutes();
  final decks = DeckSelection.of([
    for (final deck
        in await ref.read(deckRepositoryProvider).watchDecks().first)
      deck.id,
  ]);
  if (decks == null) {
    final (:day, :pace, :due, :started, dailyMinutes: _) = await readStudyDay(
      repository,
      ref.read(studyClockProvider)(),
      zone,
    );
    return MinutesPlan(
      minutes: minutes,
      due: due,
      started: started,
      unstarted: 0,
      reviews: 0,
      backlog: false,
      pace: pace,
      todayStart: day.start,
      offsetAt: zone,
    );
  }
  final today = await readToday(decks, ref);
  return MinutesPlan(
    minutes: minutes,
    due: today.due,
    started: today.started,
    unstarted: newCards(today.cards, today.states).length,
    reviews: today.count.review,
    backlog: today.count.backlog,
    pace: today.count.pace,
    todayStart: today.day.start,
    offsetAt: zone,
  );
}
