import 'package:flutter_test/flutter_test.dart';
import 'package:smartman/deck/deck.dart';
import 'package:smartman/study/src/model.dart';
import 'package:smartman/study/src/overview.dart';
import 'package:smartman/study/src/queue.dart';

import 'fixtures.dart';

final _now = DateTime.utc(2026, 10, 14, 9);

/// UTC as the device's time zone.
Duration _utc(DateTime _) => Duration.zero;

/// A state last reviewed at [lastReview] and due [interval] later.
CardState _state(DateTime lastReview, Duration interval) => CardState(
  stability: 5,
  difficulty: 5,
  lastReview: lastReview,
  due: lastReview.add(interval),
);

void main() {
  group('progress', () {
    test('a card is mastered from an interval of 21 days, learning below it, and new without a review', () {
      expect(masteredInterval, const Duration(days: 21));
      expect(
        progressOf(_state(_now, const Duration(days: 21))),
        CardProgress.mastered,
      );
      expect(
        progressOf(_state(_now, const Duration(days: 40))),
        CardProgress.mastered,
      );
      // Control: a second short of 21 days is still learning.
      expect(
        progressOf(
          _state(_now, const Duration(days: 21) - const Duration(seconds: 1)),
        ),
        CardProgress.learning,
      );
      expect(progressOf(null), CardProgress.fresh);
    });

    test('a deck counts its cards by progress, each once', () {
      final progress = DeckProgress.of(
        [
          textCard('m', createdAt: _now),
          textCard('l', createdAt: _now),
          textCard('n1', createdAt: _now),
          textCard('n2', createdAt: _now),
        ],
        {
          const CardId('m'): _state(_now, const Duration(days: 30)),
          const CardId('l'): _state(_now, const Duration(days: 2)),
          // A state of a card outside the deck counts for nothing.
          const CardId('other'): _state(_now, const Duration(days: 30)),
        },
      );
      expect(
        (progress.mastered, progress.learning, progress.fresh, progress.total),
        (1, 1, 2, 4),
      );
    });
  });

  group('forecast', () {
    test('today is the load, and each later day counts the cards due within it, from 04:00 to 04:00', () {
      final day = StudyDay.at(_now, firstAnswers: const [], offsetAt: _utc);
      final tomorrow = DateTime.utc(2026, 10, 15, 4);
      final counts = forecast(
        [
          // Due today, before the day ends: in today's load, not counted again.
          dueAt(DateTime.utc(2026, 10, 15, 3, 59)),
          // 04:00 starts tomorrow's study day.
          dueAt(tomorrow),
          dueAt(DateTime.utc(2026, 10, 16, 3, 59)),
          dueAt(DateTime.utc(2026, 10, 16, 4)),
          // The last of the seven days ends at 04:00 on 21 October.
          dueAt(DateTime.utc(2026, 10, 21, 3, 59)),
          dueAt(DateTime.utc(2026, 10, 21, 4)),
          dueAt(DateTime.utc(2026, 10, 22, 4)),
        ],
        day,
        load: 9,
        offsetAt: _utc,
      );
      expect(counts, [9, 2, 1, 0, 0, 0, 1]);
    });

    test('the days follow 04:00 local time across a change of offset', () {
      // Los Angeles leaves daylight saving time at 02:00 on 1 November 2026.
      Duration pacific(DateTime instant) =>
          instant.isBefore(DateTime.utc(2026, 11, 1, 9))
          ? const Duration(hours: -7)
          : const Duration(hours: -8);
      final now = DateTime.utc(2026, 10, 30, 18); // 11:00 on the 30th.
      final day = StudyDay.at(now, firstAnswers: const [], offsetAt: pacific);
      final counts = forecast(
        [
          // 03:00, 03:59 and 04:00 on 1 November, at UTC-8 after the change:
          // a fixed UTC-7 would start the day an hour earlier.
          dueAt(DateTime.utc(2026, 11, 1, 11)),
          dueAt(DateTime.utc(2026, 11, 1, 11, 59)),
          dueAt(DateTime.utc(2026, 11, 1, 12)),
        ],
        day,
        load: 0,
        offsetAt: pacific,
      );
      // Today (30 October), then the days starting at 04:00 on 31 October
      // and 1 November.
      expect(counts, [0, 2, 1, 0, 0, 0, 0]);
    });
  });

  group('daily goal', () {
    const a = CardId('a');
    const b = CardId('b');
    const c = CardId('c');
    final day = StudyDay.at(_now, firstAnswers: const [], offsetAt: _utc);
    ({CardId card, DateTime at}) answered(CardId card, DateTime at) =>
        (card: card, at: at);

    test('the goal is the cards answered today and those left, each once; done are those no longer left', () {
      // a answered and done; b answered "Don't know" and due again; c left.
      final goal = DailyGoal.of(
        [answered(a, _now), answered(b, _now), answered(b, _now)],
        [b, c],
        day,
      );
      expect((goal.done, goal.goal, goal.reached), (1, 3, false));
    });

    test('an answer counts from 04:00, not at 03:59, and before the next day starts', () {
      final goal = DailyGoal.of(
        [
          answered(a, DateTime.utc(2026, 10, 14, 3, 59)),
          answered(b, DateTime.utc(2026, 10, 14, 4)),
          answered(c, DateTime.utc(2026, 10, 15, 4)),
        ],
        [],
        day,
      );
      expect((goal.done, goal.goal), (1, 1));
    });

    test(
      'the day is read in the zone it is given, across a change of offset',
      () {
        // Los Angeles leaves daylight saving time at 02:00 on 1 November 2026,
        // so the day of 1 November starts at 04:00 PST, 12:00 UTC.
        Duration pacific(DateTime instant) =>
            instant.isBefore(DateTime.utc(2026, 11, 1, 9))
            ? const Duration(hours: -7)
            : const Duration(hours: -8);
        final november = StudyDay.at(
          DateTime.utc(2026, 11, 1, 20),
          firstAnswers: const [],
          offsetAt: pacific,
        );
        final goal = DailyGoal.of(
          [
            // 03:00 PST: the day before, which a fixed UTC-7 would count.
            answered(a, DateTime.utc(2026, 11, 1, 11)),
            answered(b, DateTime.utc(2026, 11, 1, 12)),
          ],
          [],
          november,
        );
        expect((goal.done, goal.goal), (1, 1));
      },
    );

    test('the goal is reached when every card of it is answered and none is left, and not on a day with none', () {
      final done = DailyGoal.of(
        [answered(a, _now), answered(b, _now)],
        [],
        day,
      );
      expect((done.done, done.goal, done.reached), (2, 2, true));
      // Control: a day that held no card has reached nothing.
      final empty = DailyGoal.of([], [], day);
      expect((empty.done, empty.goal, empty.reached), (0, 0, false));
    });
  });
}
