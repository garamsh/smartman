import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smartman/database/database.dart';
import 'package:smartman/deck/deck.dart';
import 'package:smartman/study/src/model.dart';
import 'package:smartman/study/src/queue.dart';
import 'package:smartman/study/src/rust/api/engine.dart';
import 'package:smartman/study/src/study_repository.dart';
import 'package:smartman/study/src/study_time.dart';

import 'fixtures.dart';

// The fixed histories below are the same as those of
// web/src/features/study/__tests__/study-time.test.ts, with the same expected
// figures, so the two clients compute the same figure from the same history.

/// A study day of [reviews] reviews at [reviewMs] each and [firsts] first
/// answers at [firstMs] each.
StudyDayTotal _day({
  int reviews = 20,
  int reviewMs = 4000,
  int firsts = 20,
  int firstMs = 8000,
}) => (
  reviewMs: reviews * reviewMs,
  reviews: reviews,
  firstMs: firsts * firstMs,
  firstAnswers: firsts,
);

/// Ten study days of 4 minutes: 20 reviews at 4 s and 20 first answers at 8 s.
final _steady = List.filled(10, _day());

/// UTC as the device's time zone.
Duration _utc(DateTime _) => Duration.zero;

/// 09:00 UTC on 14 October, five hours into the study day.
final _now = DateTime.utc(2026, 10, 14, 9);

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  group('the figure', () {
    test('new cards fill the daily minutes left after the due reviews, the reviews at the review pace and the new cards at the first-answer pace', () {
      final pace = paceOf(_steady);
      expect(pace, const Pace(reviewMs: 4000, firstMs: 8000));
      // (20 min - 30 reviews at 4 s) / 8 s.
      expect(dailyNewCards(minutes: 20, due: 30, pace: pace), 135);
      // (4 min - 30 reviews at 4 s) / 8 s.
      expect(dailyNewCards(minutes: 4, due: 30, pace: pace), 15);
      expect(dailyNewCards(minutes: 4, due: 0, pace: pace), 30);
    });

    test('due reviews crowd out new cards, down to none and never below', () {
      final pace = paceOf(_steady);
      // 60 reviews at 4 s fill 4 minutes; more leave none.
      expect(dailyNewCards(minutes: 4, due: 60, pace: pace), 0);
      expect(dailyNewCards(minutes: 4, due: 100, pace: pace), 0);
      // Control: one review fewer leaves room for half a card, rounded down.
      expect(dailyNewCards(minutes: 4, due: 59, pace: pace), 0);
      expect(dailyNewCards(minutes: 4, due: 58, pace: pace), 1);
    });

    test('the default is 20 minutes, the choices run from 5 to 180, and with no history every answer takes 10 s', () {
      expect(defaultDailyMinutes, 20);
      expect(dailyMinutePresets, [10, 15, 20, 30, 45, 60]);
      expect((minDailyMinutes, maxDailyMinutes), (5, 180));
      expect(paceOf(const []), Pace.unknown);
      // 20 minutes of 10 s answers, from the first day: no cold start.
      expect(
        dailyNewCards(minutes: defaultDailyMinutes, due: 0, pace: Pace.unknown),
        120,
      );
    });

    test('the day the last new card is first answered: today when today takes them all, later at the daily figure, and never with none a day', () {
      final today = studyDayStart(_now, _utc);
      DateTime? last(int remaining, int todayTakes, int perDay) =>
          lastNewCardDay(
            remaining: remaining,
            today: todayTakes,
            perDay: perDay,
            todayStart: today,
            offsetAt: _utc,
          );

      expect(last(10, 15, 15), today);
      expect(last(15, 15, 15), today);
      // 85 left after today, 15 a day: the sixth day after today.
      expect(last(100, 15, 15), DateTime.utc(2026, 10, 20, 4));
      expect(last(16, 15, 15), DateTime.utc(2026, 10, 15, 4));
      // 30 left after today, 15 a day: exactly two more days.
      expect(last(45, 15, 15), DateTime.utc(2026, 10, 16, 4));
      // Control: none a day after today never takes them all.
      expect(last(16, 15, 0), isNull);
      expect(last(15, 15, 0), today);
    });

    test(
      'a recent fast week outweighs an older slow month in the review pace',
      () {
        // 23 study days of reviews at 8 s, then 7 at 4 s, ten reviews each.
        final days = [
          ...List.filled(23, _day(reviews: 10, reviewMs: 8000)),
          ...List.filled(7, _day(reviews: 10)),
        ];

        // Nearer the week's 4 s than the month's 8.
        expect(paceOf(days).reviewMs, lessThan(6000));
      },
    );

    test('a kind with fewer than 20 answers in the window is taken at 10 s an answer', () {
      final days = [_day(reviews: 19, firsts: 20)];

      expect(paceOf(days), const Pace(reviewMs: 10000, firstMs: 8000));
    });
  });

  group('the study days read', () {
    late AppDatabase db;
    late StudyRepository study;
    var ids = 0;

    setUp(() async {
      db = AppDatabase(NativeDatabase.memory());
      study = StudyRepository(db, newId: () => 'review${ids++}');
      await db
          .into(db.decks)
          .insert(
            DecksCompanion.insert(
              id: 'deck',
              name: 'French',
              createdAt: _now,
              updatedAt: _now,
            ),
          );
    });
    tearDown(() => db.close());

    /// Stores answers to [card] at [times], each of [duration], with
    /// [state] after them.
    Future<void> answer(
      String card,
      List<DateTime> times, {
      Duration duration = const Duration(seconds: 6),
      CardState? state,
    }) async {
      await db
          .into(db.cards)
          .insertOnConflictUpdate(
            CardsCompanion.insert(
              id: card,
              deckId: 'deck',
              front: '[]',
              back: '[]',
              cardKey: card,
              source: 'manual',
              createdAt: _now,
              updatedAt: _now,
            ),
          );
      await study.record(
        CardId(card),
        [
          for (final at in times)
            Review(
              id: study.newReviewId(),
              cardId: CardId(card),
              answer: Answer.know,
              reviewedAt: at,
              duration: duration,
              fuzzFactor: FuzzFactor.draw(FirstDraw()),
            ),
        ],
        state ??
            CardState(
              stability: 30,
              difficulty: 5,
              lastReview: times.last,
              due: times.last.add(const Duration(days: 30)),
            ),
        at: times.last,
      );
    }

    /// 10:00 UTC [days] study days before [_now]'s.
    DateTime daysAgo(int days) => DateTime.utc(2026, 10, 14 - days, 10);

    test('days without an answer are left out, so the window holds the latest study days whatever rest lies between them', () async {
      // An answer of 6 s on every other day: five study days, four rests.
      for (final days in [9, 7, 5, 3, 1]) {
        await answer('card $days', [daysAgo(days)]);
      }

      final read = await readStudyDays(study, studyDayStart(_now, _utc), _utc);

      expect(read, hasLength(5));
      expect(read.first.firstMs, 6000);
    });

    test('each answer counts at most 30 s, and the stored one keeps its whole time', () async {
      await answer('idle', [daysAgo(1)], duration: const Duration(minutes: 10));

      final read = await readStudyDays(study, studyDayStart(_now, _utc), _utc);

      expect(read.single.firstMs, 30000);
      final stored = await db.select(db.reviews).getSingle();
      expect(stored.durationMs, 600000);
    });

    test('only the latest 30 study days are read, so a device holding more history computes the same figure', () async {
      // 30 study days, each of two cards answered twice in 6 s.
      for (var days = 1; days <= 30; days++) {
        for (final name in ['a', 'b']) {
          await answer('card $days $name', [
            daysAgo(days),
            daysAgo(days).add(const Duration(minutes: 1)),
          ]);
        }
      }
      final window = await readStudyDays(
        study,
        studyDayStart(_now, _utc),
        _utc,
      );
      final (day, pace) = await readStudyDay(study, _now, _utc);
      expect(window, hasLength(30));
      // (20 min - the oldest day's 2 cards, due today, at 6 s) / 6 s.
      expect(day.newCardsLeft, 198);

      // Ten earlier study days of 25 s answers, before the window: the longer
      // history another device holds, of a card with no state, so only the
      // reviews differ.
      await db.batch((batch) {
        batch.insert(
          db.cards,
          CardsCompanion.insert(
            id: 'old',
            deckId: 'deck',
            front: '[]',
            back: '[]',
            cardKey: 'old',
            source: 'manual',
            createdAt: _now,
            updatedAt: _now,
          ),
        );
        for (var days = 31; days <= 40; days++) {
          batch.insert(
            db.reviews,
            ReviewsCompanion.insert(
              id: 'old $days',
              cardId: 'old',
              rating: 'good',
              reviewedAt: daysAgo(days),
              durationMs: 25000,
              updatedAt: daysAgo(days),
            ),
          );
        }
      });

      expect(
        await readStudyDays(study, studyDayStart(_now, _utc), _utc),
        window,
      );
      final (same, samePace) = await readStudyDay(study, _now, _utc);
      expect(same.newCardsLeft, day.newCardsLeft);
      expect(samePace, pace);
      // Control: an answer inside the window is read.
      await answer('inside', [
        daysAgo(1),
      ], duration: const Duration(seconds: 25));
      expect(
        await readStudyDays(study, studyDayStart(_now, _utc), _utc),
        isNot(window),
      );
    });

    test('the day\'s new cards are read as the day stood when it started, so answering in it changes them only by the new cards taken', () async {
      // Five study days of four cards, each answered twice in 25 s, and four
      // cards due today after a 2-day interval.
      for (var days = 1; days <= 5; days++) {
        for (final name in ['a', 'b', 'c', 'd']) {
          await answer('history $days $name', [
            daysAgo(days),
            daysAgo(days).add(const Duration(minutes: 1)),
          ], duration: const Duration(seconds: 25));
        }
      }
      final dueAt = DateTime.utc(2026, 10, 14, 6);
      final due = ['due 1', 'due 2', 'due 3', 'due 4'];
      for (final card in due) {
        await answer(
          card,
          [dueAt.subtract(const Duration(days: 2))],
          state: CardState(
            stability: 2,
            difficulty: 5,
            lastReview: dueAt.subtract(const Duration(days: 2)),
            due: dueAt,
          ),
        );
      }
      final (before, _) = await readStudyDay(study, _now, _utc);

      // Every due card answered at its due time, and a new card first answered.
      for (final card in due) {
        await answer(card, [dueAt]);
      }
      await answer('new', [dueAt.add(const Duration(minutes: 1))]);
      final (after, _) = await readStudyDay(study, _now, _utc);

      // The figure leaves room for more than the one new card taken, and is
      // the same before and after, less that card.
      expect(before.newCardsLeft, greaterThan(1));
      expect(after.newCardsLeft, before.newCardsLeft - 1);
    });

    test('the daily minutes the user stores apply to today at once, and the default holds until then', () async {
      await answer('known', [daysAgo(1)]);
      final (unset, pace) = await readStudyDay(study, _now, _utc);
      expect(await study.dailyMinutes(), defaultDailyMinutes);
      expect(
        unset.newCardsLeft,
        dailyNewCards(minutes: defaultDailyMinutes, due: 0, pace: pace),
      );

      await study.setDailyMinutes(5, at: _now);
      final (changed, _) = await readStudyDay(study, _now, _utc);

      expect(await study.dailyMinutes(), 5);
      expect(
        changed.newCardsLeft,
        dailyNewCards(minutes: 5, due: 0, pace: pace),
      );
      expect(changed.newCardsLeft, lessThan(unset.newCardsLeft));
      final row = await db.select(db.studySettings).getSingle();
      expect((row.dailyMinutes, row.dirty), (5, true));
    });
  });
}
