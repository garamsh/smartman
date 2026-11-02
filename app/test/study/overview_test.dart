import 'package:flutter_test/flutter_test.dart';
import 'package:knowno/deck/deck.dart';
import 'package:knowno/study/src/model.dart';
import 'package:knowno/study/src/overview.dart';
import 'package:knowno/study/src/queue.dart';
import 'package:knowno/study/src/rust/api/engine.dart';
import 'package:knowno/study/src/today.dart';

import 'fixtures.dart';

/// The new cards a study day takes in these cases, as the daily minutes would
/// set them.
const _quota = 20;

final _now = DateTime.utc(2026, 10, 14, 9);

/// UTC as the device's time zone.
/// Los Angeles, which left daylight saving time at 02:00 on 2 November
/// 2025.
Duration _pacific(DateTime instant) =>
    instant.isBefore(DateTime.utc(2025, 11, 2, 9))
    ? const Duration(hours: -7)
    : const Duration(hours: -8);

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

  group('next review', () {
    test(
      'is the first later day with a card due, each day from 04:00 to 04:00',
      () {
        final day = StudyDay.at(
          _now,
          firstAnswers: const {},
          newCards: _quota,
          offsetAt: _utc,
        );
        expect(
          nextReviewOf(
            [
              // Due today, before the day ends: not a later day's.
              dueAt(DateTime.utc(2026, 10, 15, 3, 59)),
              // 04:00 starts tomorrow's study day.
              dueAt(DateTime.utc(2026, 10, 15, 4)),
              dueAt(DateTime.utc(2026, 10, 16, 3, 59)),
              dueAt(DateTime.utc(2026, 10, 16, 4)),
            ],
            day,
            offsetAt: _utc,
          ),
          (after: 1, cards: 2),
        );
        // The last of the seven days ends at 04:00 on 21 October.
        expect(
          nextReviewOf(
            [dueAt(DateTime.utc(2026, 10, 21, 3, 59))],
            day,
            offsetAt: _utc,
          ),
          (after: 6, cards: 1),
        );
        expect(
          nextReviewOf(
            [
              dueAt(DateTime.utc(2026, 10, 15, 3, 59)),
              dueAt(DateTime.utc(2026, 10, 21, 4)),
            ],
            day,
            offsetAt: _utc,
          ),
          isNull,
        );
      },
    );

    test('follows 04:00 local time across a change of offset', () {
      final now = DateTime.utc(2025, 10, 31, 18); // 11:00 on the 31st.
      final day = StudyDay.at(
        now,
        firstAnswers: const {},
        newCards: _quota,
        offsetAt: _pacific,
      );
      // 03:00 and 03:59 on 2 November, at UTC-8 after the change, are still
      // 1 November's; a fixed UTC-7 would start 2 November an hour earlier.
      expect(
        nextReviewOf(
          [
            dueAt(DateTime.utc(2025, 11, 2, 11)),
            dueAt(DateTime.utc(2025, 11, 2, 11, 59)),
          ],
          day,
          offsetAt: _pacific,
        ),
        (after: 1, cards: 2),
      );
    });
  });

  group('the last seven days', () {
    // The same history as web/src/app/(shell)/__tests__/today.test.tsx's
    // last seven days, with the same figures.
    test('count each study day\'s cards once and its time, each answer up to 30 s, across a gap, 04:00 and a change of offset, today partial', () {
      StoredAnswer answer(String card, DateTime at, int seconds) => (
        card: CardId(card),
        answer: Answer.know,
        at: at,
        duration: Duration(seconds: seconds),
      );
      // 10:00 on 5 November 2025 in Los Angeles, after the change to UTC-8.
      final now = DateTime.utc(2025, 11, 5, 18);
      final week = lastWeek(
        [
          // 29 October, before the seven days.
          answer('a', DateTime.utc(2025, 10, 29, 15), 10),
          // 30 October: a twice and b, whose 45 s count as 30.
          answer('a', DateTime.utc(2025, 10, 30, 18), 10),
          answer('b', DateTime.utc(2025, 10, 30, 18, 5), 45),
          answer('a', DateTime.utc(2025, 10, 30, 18, 10), 5),
          // 03:59 on 1 November is still 31 October's.
          answer('c', DateTime.utc(2025, 11, 1, 10, 59), 20),
          // 04:00 on 1 November starts its day.
          answer('d', DateTime.utc(2025, 11, 1, 11), 20),
          // 03:30 on 2 November at UTC-8 is still 1 November's.
          answer('e', DateTime.utc(2025, 11, 2, 11, 30), 10),
          // 04:30 on 2 November.
          answer('f', DateTime.utc(2025, 11, 2, 12, 30), 10),
          // 3 November; 4 November has none.
          answer('a', DateTime.utc(2025, 11, 3, 20), 10),
          answer('b', DateTime.utc(2025, 11, 3, 20, 1), 10),
          // Today so far, 90 s counting as 30.
          answer('g', DateTime.utc(2025, 11, 5, 17), 30),
          answer('h', DateTime.utc(2025, 11, 5, 17, 30), 90),
        ],
        studyDayStart(now, _pacific),
        _pacific,
      );
      expect([for (final day in week) day.date.day], [30, 31, 1, 2, 3, 4, 5]);
      expect([for (final day in week) day.cards], [2, 1, 2, 1, 2, 0, 2]);
      expect(
        [for (final day in week) day.time.inSeconds],
        [45, 20, 30, 10, 20, 0, 60],
      );
      // Control: at a fixed UTC-7, 03:30 on 2 November would be 04:30, its
      // own day's.
      Duration summer(DateTime _) => const Duration(hours: -7);
      final fixed = lastWeek(
        [answer('e', DateTime.utc(2025, 11, 2, 11, 30), 10)],
        studyDayStart(now, summer),
        summer,
      );
      expect([for (final day in fixed) day.cards], [0, 0, 0, 1, 0, 0, 0]);
    });
  });

  group('daily goal', () {
    final day = StudyDay.at(
      _now,
      firstAnswers: const {},
      newCards: _quota,
      offsetAt: _utc,
    );
    final tomorrow = DateTime.utc(2026, 10, 15, 9);
    Card card(String name) =>
        textCard(name, createdAt: DateTime.utc(2026, 9, 1));
    DayAnswer know(String name, DateTime at) =>
        (card: CardId(name), answer: Answer.know, at: at);
    DayAnswer dontKnow(String name, DateTime at) =>
        (card: CardId(name), answer: Answer.dontKnow, at: at);

    test("the goal is the day's cards done and left as today's list places them, a card on Don't know left until Know", () {
      final cards = [card('a'), card('b'), card('c')];
      final states = {
        const CardId('a'): dueAt(tomorrow),
        const CardId('b'): dueAt(tomorrow),
        const CardId('c'): dueAt(_now),
      };
      // a done; b answered "Don't know", which its state makes due tomorrow;
      // c due and not answered.
      final goal = DailyGoal.of(
        dayPlanOf(cards, states, day, [know('a', _now), dontKnow('b', _now)]),
      );
      expect((goal.done, goal.goal, goal.reached), (1, 3, false));
      // Answered "Know" later, b is done.
      final later = DailyGoal.of(
        dayPlanOf(cards, states, day, [
          know('a', _now),
          dontKnow('b', _now),
          know('b', _now.add(const Duration(minutes: 1))),
        ]),
      );
      expect((later.done, later.goal), (2, 3));
    });

    test('an answer counts from 04:00, not at 03:59, and before the next day starts', () {
      final cards = [card('a'), card('b'), card('c')];
      final states = {for (final card in cards) card.id: dueAt(tomorrow)};
      final goal = DailyGoal.of(
        dayPlanOf(cards, states, day, [
          know('a', DateTime.utc(2026, 10, 14, 3, 59)),
          know('b', DateTime.utc(2026, 10, 14, 4)),
          know('c', DateTime.utc(2026, 10, 15, 4)),
        ]),
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
          firstAnswers: const {},
          newCards: _quota,
          offsetAt: pacific,
        );
        final cards = [card('a'), card('b')];
        final states = {
          for (final card in cards) card.id: dueAt(DateTime.utc(2026, 11, 3)),
        };
        final goal = DailyGoal.of(
          dayPlanOf(cards, states, november, [
            // 03:00 PST: the day before, which a fixed UTC-7 would count.
            know('a', DateTime.utc(2026, 11, 1, 11)),
            know('b', DateTime.utc(2026, 11, 1, 12)),
          ]),
        );
        expect((goal.done, goal.goal), (1, 1));
      },
    );

    test('the goal is reached when every card of it is done and none is left, and not on a day with none', () {
      final cards = [card('a'), card('b')];
      final states = {for (final card in cards) card.id: dueAt(tomorrow)};
      final done = DailyGoal.of(
        dayPlanOf(cards, states, day, [know('a', _now), know('b', _now)]),
      );
      expect((done.done, done.goal, done.reached), (2, 2, true));
      // Control: a day that held no card has reached nothing.
      final empty = DailyGoal.of(dayPlanOf(const [], const {}, day, const []));
      expect((empty.done, empty.goal, empty.reached), (0, 0, false));
    });
  });

  group('catch-up', () {
    test('a backlog falls by the pace each day, to zero and not below', () {
      expect(catchUp(84, 30), [84, 54, 24, 0, 0, 0, 0]);
      // Control: a pace of one keeps a backlog of seven on every day.
      expect(catchUp(7, 1), [7, 6, 5, 4, 3, 2, 1]);
    });
  });
}
