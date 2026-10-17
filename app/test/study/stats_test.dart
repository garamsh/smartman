import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smartman/database/database.dart';
import 'package:smartman/deck/deck.dart';
import 'package:smartman/study/src/model.dart';
import 'package:smartman/study/src/rust/api/engine.dart';
import 'package:smartman/study/src/scheduler.dart';
import 'package:smartman/study/src/session.dart';
import 'package:smartman/study/src/stats.dart';
import 'package:smartman/study/src/study_repository.dart';

import 'fixtures.dart';

/// UTC as the device's time zone.
Duration _utc(DateTime _) => Duration.zero;

/// Seoul's time zone, nine hours ahead of UTC.
Duration _seoul(DateTime _) => const Duration(hours: 9);

/// 09:00 UTC on Wednesday 14 October, five hours into the study day.
final _now = DateTime.utc(2026, 10, 14, 9);

StoredAnswer _answer(String card, Answer answer, DateTime at) =>
    (card: CardId(card), answer: answer, at: at, duration: Duration.zero);

/// A state last reviewed at [lastReview] and due [days] days later.
CardState _state(DateTime lastReview, int days) => CardState(
  stability: 5,
  difficulty: 5,
  lastReview: lastReview,
  due: lastReview.add(Duration(days: days)),
);

const _know = Answer.know;
const _dontKnow = Answer.dontKnow;

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  group('retention', () {
    test('counts each card\'s first answer of a study day after an earlier day, from 04:00, and not its first answer ever or a re-show', () {
      final days = retentionByDay([
        // Given out of order: the function orders them itself.
        _answer('a', _know, DateTime.utc(2026, 10, 12, 9)),
        // A card's first answer ever is not scheduled.
        _answer('a', _dontKnow, DateTime.utc(2026, 10, 10, 9)),
        _answer('b', _know, DateTime.utc(2026, 10, 10, 9)),
        _answer('b', _dontKnow, DateTime.utc(2026, 10, 12, 10)),
        // A re-show after "Don't know" on the same day is not scheduled.
        _answer('b', _know, DateTime.utc(2026, 10, 12, 10, 5)),
        // 03:59 is the end of 11 October's study day, so 04:00 is a later
        // one and scheduled.
        _answer('c', _dontKnow, DateTime.utc(2026, 10, 12, 3, 59)),
        _answer('c', _know, DateTime.utc(2026, 10, 12, 4)),
        // Control: from 04:00 to 05:00 is one study day, so not scheduled.
        _answer('d', _dontKnow, DateTime.utc(2026, 10, 12, 4)),
        _answer('d', _know, DateTime.utc(2026, 10, 12, 5)),
      ], offsetAt: _utc);

      expect(
        [
          for (final (:day, :retention) in days)
            (day, retention.reviews, retention.known),
        ],
        [(DateTime.utc(2026, 10, 12, 4), 3, 2)],
      );
    });

    test('a period\'s retention is its days\' known reviews over their reviews, with its gap to the 90% target', () {
      final days = retentionByDay([
        for (final card in ['a', 'b', 'c', 'd', 'e'])
          _answer(card, _know, DateTime.utc(2026, 10, 10, 9)),
        for (final card in ['a', 'b', 'c'])
          _answer(card, _know, DateTime.utc(2026, 10, 11, 9)),
        _answer('d', _dontKnow, DateTime.utc(2026, 10, 11, 9)),
        _answer('e', _know, DateTime.utc(2026, 10, 12, 9)),
      ], offsetAt: _utc);
      final total = retentionOver(days)!;

      expect(targetRetention, 0.9);
      expect((total.reviews, total.known), (5, 4));
      expect(total.share, closeTo(0.8, 1e-12));
      expect(total.gap, closeTo(-0.1, 1e-12));
      expect(retentionOver(days.take(0)), isNull);
    });
  });

  group('recall bands', () {
    test('split cards at 0.95 and 0.8, each bound in the upper band, with the mean', () {
      final bands = RecallBands.of([1, 0.95, 0.9499, 0.8, 0.7999]);

      expect((bands.strong, bands.fair, bands.fading), (2, 2, 1));
      expect(
        bands.mean,
        closeTo((1 + 0.95 + 0.9499 + 0.8 + 0.7999) / 5, 1e-12),
      );
      expect(RecallBands.of(const []).mean, isNull);
    });
  });

  group('mastered by week', () {
    test('counts the cards mastered at the end of each of the last eight weeks, each week ending at 04:00', () {
      // The weeks end at 04:00 on 27 August, 3, 10, 17 and 24 September, and
      // 1, 8 and 15 October.
      final weeks = masteredByWeek(
        [
          // Learning, then mastered by a review at 03:59 on 8 October.
          [
            _state(DateTime.utc(2026, 9, 1, 9), 2),
            _state(DateTime.utc(2026, 10, 8, 3, 59), 30),
          ],
          // Control: mastered at 04:00 on 8 October, in the week after.
          [_state(DateTime.utc(2026, 10, 8, 4), 30)],
          // Mastered on 10 September after 04:00, then forgotten on 10 October.
          [
            _state(DateTime.utc(2026, 9, 10, 5), 25),
            _state(DateTime.utc(2026, 10, 10, 9), 1),
          ],
          // Never mastered.
          [_state(DateTime.utc(2026, 9, 1, 9), 20)],
        ],
        _now,
        offsetAt: _utc,
      );

      expect(weeks, [0, 0, 0, 1, 1, 1, 2, 2]);
    });
  });

  group('study days', () {
    test('count the distinct cards answered on each of the last 84 study days, from 04:00 in the device\'s zone', () {
      // Seoul's 04:00 on 14 October is 19:00 UTC on 13 October.
      final days = studyDayCounts(
        [
          _answer('a', _know, DateTime.utc(2026, 10, 13, 18, 59)),
          _answer('a', _know, DateTime.utc(2026, 10, 13, 19)),
          // The same card twice in a day is one card.
          _answer('a', _dontKnow, DateTime.utc(2026, 10, 13, 20)),
          _answer('b', _know, DateTime.utc(2026, 10, 13, 21)),
          // 03:59 on 23 July in Seoul ends 22 July's study day, outside the
          // twelve weeks; 04:00 starts the first of the 84 days.
          _answer('c', _know, DateTime.utc(2026, 7, 22, 18, 59)),
          _answer('d', _know, DateTime.utc(2026, 7, 22, 19)),
        ],
        _now,
        offsetAt: _seoul,
      );

      expect(days, hasLength(84));
      expect(days.first, (date: DateTime.utc(2026, 7, 23), cards: 1));
      expect(days[days.length - 2], (
        date: DateTime.utc(2026, 10, 13),
        cards: 1,
      ));
      expect(days.last, (date: DateTime.utc(2026, 10, 14), cards: 2));
      expect(days.fold(0, (sum, day) => sum + day.cards), 4);
    });

    test('the best streak is the longest run of study days with an answer, from 04:00', () {
      final best = bestStreak([
        DateTime.utc(2026, 10, 1, 9),
        DateTime.utc(2026, 10, 2, 9),
        DateTime.utc(2026, 10, 3, 9),
        // 03:59 on 5 October ends 4 October's study day: a fourth day in a row.
        DateTime.utc(2026, 10, 5, 3, 59),
        // Control: after a gap, a run of two.
        DateTime.utc(2026, 10, 9, 4),
        DateTime.utc(2026, 10, 10, 9),
      ], offsetAt: _utc);

      expect(best, 4);
      expect(bestStreak(const [], offsetAt: _utc), 0);
    });
  });

  group('read from the device', () {
    late Scheduler scheduler;
    setUpAll(() async => scheduler = await Scheduler.load());

    test('counts every stored answer, a deleted card\'s included, in the retention, the days and the streaks, and only cards in the decks in the bands and the weeks; practice adds nothing', () async {
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      var ids = 0;
      final cards = DeckRepository(
        db,
        clock: () => DateTime.utc(2026, 9, 1),
        newId: () => 'id${ids++}',
      );
      final repository = StudyRepository(db, newId: () => 'review${ids++}');
      final deck = await cards.createDeck('French');
      final names = <String, CardId>{};
      for (final name in ['a', 'b', 'gone']) {
        final saved = await cards.addCard(
          deck.id,
          front: [TextContent(name)],
          back: [TextContent(name)],
        );
        names[name] = switch (saved) {
          CardSaved(:final card) => card.id,
          DuplicateFront() => fail('the setup saved a duplicate'),
        };
      }
      Future<void> store(String name, List<(Answer, DateTime)> answers) async {
        final card = names[name]!;
        final reviews = [
          for (final (answer, at) in answers)
            Review(
              id: repository.newReviewId(),
              cardId: card,
              answer: answer,
              reviewedAt: at,
              duration: Duration.zero,
              fuzzFactor: FuzzFactor.draw(FirstDraw()),
            ),
        ];
        CardState? state;
        for (final review in reviews) {
          state = await scheduler.review(
            state,
            review.answer,
            review.reviewedAt,
            fuzz: review.fuzzFactor,
          );
        }
        await repository.record(card, reviews, state!, at: answers.last.$2);
      }

      final tenth = DateTime.utc(2026, 10, 10, 9);
      final thirteenth = DateTime.utc(2026, 10, 13, 9);
      await store('a', [(_know, tenth), (_know, thirteenth)]);
      await store('b', [(_know, tenth), (_dontKnow, thirteenth)]);
      await store('gone', [(_know, tenth), (_know, thirteenth)]);
      await cards.deleteCard(names['gone']!);

      Future<StudyStats> read([DateTime? at]) => readStats(
        DeckSelection(deck.id),
        cards: cards,
        repository: repository,
        scheduler: scheduler,
        now: at ?? _now,
        offsetAt: _utc,
      );
      final before = await read();
      final states = await repository.statesOf([names['a']!, names['b']!]);
      final recalls = [
        for (final state in states.values)
          await scheduler.retrievability(state, _now),
      ];

      expect(states, hasLength(2), reason: 'the setup stored both states');
      expect(_retention(before), [(DateTime.utc(2026, 10, 13, 4), 3, 2)]);
      expect(_studied(before), [
        (DateTime.utc(2026, 10, 10), 3),
        (DateTime.utc(2026, 10, 13), 3),
      ]);
      expect((before.streak, before.bestStreak), (1, 1));
      // The deleted card keeps its state, but not its place in the bands.
      expect(_bands(before.recall), _bands(RecallBands.of(recalls)));
      expect(
        before.recall.strong + before.recall.fair + before.recall.fading,
        2,
      );
      expect(before.mastered, hasLength(masteredWeeks));

      // b, answered "Don't know" yesterday, is due today.
      final session = StudySession(
        decks: DeckSelection(deck.id),
        cards: cards,
        repository: repository,
        scheduler: scheduler,
        clock: () => _now,
        random: FirstDraw(),
        onFailure: (failure) => fail('unexpected $failure'),
        offsetAt: _utc,
      );
      addTearDown(session.dispose);
      await untilLoaded(session);
      session.answer(_know);
      await session.settled;
      expect(session.state, isA<SessionComplete>());
      final studied = await read();

      // Control: the session's stored answer is counted.
      expect(_retention(studied), [
        (DateTime.utc(2026, 10, 13, 4), 3, 2),
        (DateTime.utc(2026, 10, 14, 4), 1, 1),
      ]);
      expect((studied.streak, studied.bestStreak), (2, 2));

      // Read three days on, where a state a written practice answer changed
      // would show in the bands: at the answer's own time every recall is 1.
      final later = _now.add(const Duration(days: 3));
      final unpractised = await read(later);
      session.practice();
      for (final answer in [_dontKnow, _know, _know, _dontKnow]) {
        session.answer(answer);
      }
      await session.settled;
      final practised = await read(later);

      expect(_retention(practised), _retention(unpractised));
      expect(_studied(practised), _studied(unpractised));
      expect(
        (practised.streak, practised.bestStreak),
        (unpractised.streak, unpractised.bestStreak),
      );
      expect(_bands(practised.recall), _bands(unpractised.recall));
      expect(practised.mastered, unpractised.mastered);
    });
  });
}

List<(DateTime, int, int)> _retention(StudyStats stats) => [
  for (final (:day, :retention) in stats.retention)
    (day, retention.reviews, retention.known),
];

List<(DateTime, int)> _studied(StudyStats stats) => [
  for (final (:date, :cards) in stats.days)
    if (cards > 0) (date, cards),
];

(int, int, int, double?) _bands(RecallBands bands) =>
    (bands.strong, bands.fair, bands.fading, bands.mean);
