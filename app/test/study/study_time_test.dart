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
    test('a steady history sets aside its reviews at the review pace and fills the rest of its study time with new cards at the first-answer pace', () {
      expect(studyTime(_steady), 240000);
      expect(paceOf(_steady), const Pace(reviewMs: 4000, firstMs: 8000));
      // (240 s - 30 reviews at 4 s) / 8 s.
      expect(dailyNewCards(_steady, due: 30, load: 30), 15);
    });

    test('reviews due beyond the daily load crowd out new cards, spread over a week, down to none', () {
      expect(dailyNewCards(_steady, due: 30, load: 30), 15);
      // 30 + 30 / 7 reviews set aside: (240 - 137.1) s / 8 s.
      expect(dailyNewCards(_steady, due: 60, load: 30), 12);
      expect(dailyNewCards(_steady, due: 90, load: 30), 10);
      // The daily load alone fills the study time, and more leaves none.
      expect(dailyNewCards(_steady, due: 60, load: 60), 0);
      expect(dailyNewCards(_steady, due: 100, load: 70), 0);
      // Fewer due than the daily load set aside the load.
      expect(dailyNewCards(_steady, due: 0, load: 30), 15);
    });

    test(
      'a cold start takes 20 new cards until the window holds five study days',
      () {
        expect(coldStartNewCards, 20);
        expect(coldStartStudyDays, 5);
        expect(dailyNewCards(_steady.sublist(0, 4), due: 0, load: 0), 20);
        expect(dailyNewCards(const [], due: 0, load: 0), 20);
        // Control: from five study days the figure is the user's own.
        expect(dailyNewCards(_steady.sublist(0, 5), due: 30, load: 30), 15);
      },
    );

    test('the study time moves at most 10% from one study day to the next', () {
      // A day of 10 minutes after ten of 4: 50 reviews and 50 first answers.
      final jump = [..._steady, _day(reviews: 50, firsts: 50)];

      expect(studyTime(_steady), 240000);
      expect(studyTime(jump), 264000);
      // (264 s - 120 s) / 8 s.
      expect(dailyNewCards(jump, due: 30, load: 30), 18);
    });

    test(
      'a recent long week outweighs an older short month in the study time',
      () {
        // 23 study days of 2 minutes, then 7 of 4.
        final days = [
          ...List.filled(23, _day(reviews: 10, firsts: 10)),
          ...List.filled(7, _day()),
        ];
        final plainMean = (23 * 120000 + 7 * 240000) / 30;

        expect(plainMean, 148000);
        // Nearer the week's 4 minutes than the month's 2.
        expect(studyTime(days), greaterThan(180000));
      },
    );

    test('a recent fast week pulls the review pace below the plain mean of the window', () {
      // 23 study days of reviews at 8 s, then 7 at 4 s, ten reviews each.
      final days = [
        ...List.filled(23, _day(reviews: 10, reviewMs: 8000)),
        ...List.filled(7, _day(reviews: 10)),
      ];
      final plainMean = (23 * 8000 + 7 * 4000) / 30;

      expect(paceOf(days).reviewMs, lessThan(plainMean - 500));
    });

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

    test(
      'days without an answer are left out, so rest lowers no study time',
      () async {
        // An answer of 6 s on every other day: five study days, four rests.
        for (final days in [9, 7, 5, 3, 1]) {
          await answer('card $days', [daysAgo(days)]);
        }

        final read = await readStudyDays(
          study,
          studyDayStart(_now, _utc),
          _utc,
        );

        expect(read, hasLength(5));
        expect(studyTime(read), 6000);
        // Control: the same answers counted with the rests as days of no time.
        final withRests = [
          for (final day in read) ...[
            day,
            (reviewMs: 0, reviews: 0, firstMs: 0, firstAnswers: 0),
          ],
        ]..removeLast();
        expect(studyTime(withRests), lessThan(6000));
      },
    );

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
      // (24 s - a load of 2 reviews at 6 s) / 6 s.
      expect(day.newCardsLeft, 2);

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
  });
}
