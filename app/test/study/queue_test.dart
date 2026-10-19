import 'dart:math';

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

/// The new cards a study day takes in these cases, as the daily minutes would
/// set them.
const _quota = 20;

/// The new cards a day takes over [_Decks], whose stored daily minutes are 5.
const _storedQuota = 30;

final _now = DateTime.utc(2026, 10, 14, 9);

/// UTC as the device's time zone.
Duration _utc(DateTime _) => Duration.zero;

/// The study day holding [_now] in UTC, with no new card answered in it.
final _today = StudyDay.at(
  _now,
  firstAnswers: const {},
  newCards: _quota,
  offsetAt: _utc,
);

List<String> _names(List<Card> cards) => [
  for (final card in cards) card.id.value,
];

/// Three decks in one database: "a" and "b" hold cards created alternately,
/// one minute apart, and "empty" holds none.
class _Decks {
  _Decks._(this.cards, this.study, this.ids);

  final DeckRepository cards;
  final StudyRepository study;

  /// Each deck's id by name.
  final Map<String, DeckId> ids;

  static Future<_Decks> open() async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    var created = DateTime.utc(2026, 9, 1);
    final cards = DeckRepository(
      db,
      clock: () => created = created.add(const Duration(minutes: 1)),
      newId: _counter('id'),
    );
    final study = StudyRepository(db, newId: _counter('review'));
    // 5 minutes at 10 s a card, the pace while too few answers are stored:
    // [_storedQuota] new cards a day.
    await study.setDailyMinutes(5, at: created);
    return _Decks._(cards, study, {
      for (final name in ['a', 'b', 'empty'])
        name: (await cards.createDeck(name)).id,
    });
  }

  /// Adds a card to [deck] whose front is [front], with a stored state due
  /// at [due] when one is given.
  Future<void> add(String deck, String front, {DateTime? due}) async {
    final saved = await cards.addCard(
      ids[deck]!,
      front: [TextContent(front)],
      back: [TextContent(front)],
    );
    final card = switch (saved) {
      CardSaved(:final card) => card,
      DuplicateFront() => fail('the deck held no duplicate'),
    };
    if (due == null) return;
    final state = dueAt(due);
    await study.record(
      card.id,
      [
        Review(
          id: study.newReviewId(),
          cardId: card.id,
          answer: Answer.know,
          reviewedAt: state.lastReview,
          duration: Duration.zero,
          fuzzFactor: FuzzFactor.draw(FirstDraw()),
        ),
      ],
      state,
      at: DateTime.utc(2026, 9, 1),
    );
  }

  /// Adds a new card to [deck] and answers it for the first time [at], so
  /// it is next due a week later.
  Future<void> firstAnswer(String deck, String front, DateTime at) async {
    final saved = await cards.addCard(
      ids[deck]!,
      front: [TextContent(front)],
      back: [TextContent(front)],
    );
    final card = switch (saved) {
      CardSaved(:final card) => card,
      DuplicateFront() => fail('the deck held no duplicate'),
    };
    await study.record(
      card.id,
      [
        Review(
          id: study.newReviewId(),
          cardId: card.id,
          answer: Answer.know,
          reviewedAt: at,
          duration: Duration.zero,
          fuzzFactor: FuzzFactor.draw(FirstDraw()),
        ),
      ],
      CardState(
        stability: 7,
        difficulty: 5,
        lastReview: at,
        due: at.add(const Duration(days: 7)),
      ),
      at: at,
    );
  }

  /// The study day holding [now] in the time zone [offsetAt] gives, from the
  /// answers and states stored across every deck.
  Future<StudyDay> day(DateTime now, UtcOffsetAt offsetAt) async =>
      (await readStudyDay(study, now, offsetAt)).day;

  /// The fronts of the cards a session over [decks] would study in [day].
  Future<List<String>> queueIn(List<String> decks, StudyDay day) async {
    final (read, states) = await readCards(
      DeckSelection.of([for (final deck in decks) ids[deck]!])!,
      cards,
      study,
    );
    return [
      for (final card in selectQueue(read, states, day).cards)
        plainText(card.front),
    ];
  }

  /// The fronts of the cards a session over [decks] would study now.
  Future<List<String>> queue(List<String> decks) async {
    final (read, states) = await readCards(
      DeckSelection.of([for (final deck in decks) ids[deck]!])!,
      cards,
      study,
    );
    return [
      for (final card in selectQueue(read, states, _today).cards)
        plainText(card.front),
    ];
  }
}

/// A state due at [due] after an interval of [days] days.
CardState _dueAfter(DateTime due, {required int days}) => CardState(
  stability: days.toDouble(),
  difficulty: 5,
  lastReview: due.subtract(Duration(days: days)),
  due: due,
);

String Function() _counter(String prefix) {
  var next = 0;
  return () => '$prefix${next++}';
}

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  group('membership', () {
    test('a session over several decks takes every card due by the end of the study day in them and the 20 oldest new cards across them', () async {
      final decks = await _Decks.open();
      // Created alternately, so the oldest twenty new cards are the first
      // ten of each deck.
      for (var index = 0; index < 15; index++) {
        await decks.add('a', 'a new $index');
        await decks.add('b', 'b new $index');
      }
      for (final deck in ['a', 'b']) {
        await decks.add(deck, '$deck due', due: _now);
        await decks.add(
          deck,
          '$deck overdue',
          due: _now.subtract(const Duration(days: 9)),
        );
        await decks.add(
          deck,
          '$deck later today',
          due: DateTime.utc(2026, 10, 15, 3, 59),
        );
        await decks.add(
          deck,
          '$deck tomorrow',
          due: DateTime.utc(2026, 10, 15, 4),
        );
      }

      expect(
        await decks.queue(['a', 'b', 'empty']),
        unorderedEquals([
          'a due',
          'a overdue',
          'a later today',
          'b due',
          'b overdue',
          'b later today',
          for (var index = 0; index < 10; index++) ...[
            'a new $index',
            'b new $index',
          ],
        ]),
      );
      // Control: one deck selected alone keeps all fifteen of its new cards
      // and none of the other deck's cards.
      expect(
        await decks.queue(['a']),
        unorderedEquals([
          'a due',
          'a overdue',
          'a later today',
          for (var index = 0; index < 15; index++) 'a new $index',
        ]),
      );
    });

    test('a deck with no card adds nothing to a selection, and alone selects nothing', () async {
      final decks = await _Decks.open();
      await decks.add('a', 'a new');
      await decks.add('a', 'a due', due: _now);

      expect(await decks.queue(['empty']), isEmpty);
      // Control: the same deck beside one with cards leaves that deck's
      // queue as it was.
      expect(
        await decks.queue(['a', 'empty']),
        unorderedEquals(['a due', 'a new']),
      );
    });
  });

  group('order', () {
    final due = [
      for (var index = 0; index < 10; index++)
        textCard('due$index', createdAt: _now),
    ];
    final fresh = [
      for (var index = 0; index < 10; index++)
        textCard(
          'new$index',
          createdAt: _now.subtract(Duration(days: 10 - index)),
        ),
    ];
    // Due daily, so ten due cards are one day of reviews: no backlog.
    final selected = selectQueue(
      [...due, ...fresh],
      {for (final card in due) card.id: _dueAfter(_now, days: 1)},
      _today,
    );

    test('the same seed gives the same order, and different seeds different orders, of the same cards', () {
      final first = _names(orderQueue(selected, Random(1)));

      expect(_names(orderQueue(selected, Random(1))), first);
      expect(first, unorderedEquals(_names(selected.cards)));
      final second = _names(orderQueue(selected, Random(2)));
      expect(second, unorderedEquals(_names(selected.cards)));
      expect(second, isNot(first));
    });

    test('new cards are placed among the due cards, not after them, under every seed', () {
      expect(selected.backlog, isFalse);
      expect(_names(selected.cards), [..._names(due), ..._names(fresh)]);
      for (var seed = 0; seed < 100; seed++) {
        final ordered = _names(orderQueue(selected, Random(seed)));
        final firstNew = ordered.indexWhere((name) => name.startsWith('new'));
        final lastDue = ordered.lastIndexWhere(
          (name) => name.startsWith('due'),
        );

        expect(firstNew, lessThan(lastDue), reason: 'seed $seed: $ordered');
      }
    });

    test('a card put back comes after 3 to 5 other cards, each gap drawn, or after all that remain', () {
      expect((reshowGapMin, reshowGapMax), (3, 5));
      final again = textCard('again', createdAt: _now);
      final gaps = <int>{};
      for (var seed = 0; seed < 100; seed++) {
        final random = Random(seed);
        for (var remaining = 0; remaining <= 7; remaining++) {
          final queue = due.sublist(0, remaining);
          reinsert(queue, again, random);
          final gap = queue.indexOf(again);

          expect(
            gap,
            inInclusiveRange(min(3, remaining), min(5, remaining)),
            reason: 'seed $seed with $remaining remaining',
          );
          if (remaining >= 5) gaps.add(gap);
        }
      }
      expect(gaps, {3, 4, 5});
    });
  });

  group('backlog', () {
    /// [count] reviewed cards, each after an interval of four days, so their
    /// daily load is a quarter of [count]; the first [due] of them are due.
    (List<Card>, Map<CardId, CardState>) reviewed(
      int count, {
      required int due,
    }) {
      final cards = [
        for (var index = 0; index < count; index++)
          textCard('review$index', createdAt: _now),
      ];
      return (
        cards,
        {
          for (final (index, card) in cards.indexed)
            card.id: _dueAfter(
              index < due ? _now : _now.add(const Duration(days: 1)),
              days: 4,
            ),
        },
      );
    }

    final fresh = [
      for (var index = 0; index < 2; index++)
        textCard('new$index', createdAt: _now),
    ];

    test('new cards pause once more than three days of reviews are due, and are taken at three', () {
      expect(backlogDays, 3);
      // Twelve cards due every four days are three reviews a day.
      final (atThreshold, atStates) = reviewed(12, due: 9);
      final (over, overStates) = reviewed(12, due: 10);

      expect(dailyLoad(atStates.values), 3);
      final current = selectQueue([...atThreshold, ...fresh], atStates, _today);
      final paused = selectQueue([...over, ...fresh], overStates, _today);

      expect(current.backlog, isFalse);
      expect(
        _names(current.cards),
        unorderedEquals([
          ..._names(atThreshold.take(9).toList()),
          'new0',
          'new1',
        ]),
      );
      expect(paused.backlog, isTrue);
      expect(
        _names(paused.cards),
        unorderedEquals(_names(over.take(10).toList())),
      );
    });

    // Thirty cards due at distinct times, each after a 30-day interval:
    // thirty due against a daily load of one is a backlog.
    final overdue = [
      for (var index = 0; index < 30; index++)
        textCard('overdue$index', createdAt: _now),
    ];
    final overdueStates = {
      for (final (index, card) in overdue.indexed)
        card.id: _dueAfter(_now.subtract(Duration(hours: index)), days: 30),
    };
    // Read latest due first, so only sorting puts the earliest first.
    final latestFirst = overdue;
    final earliestFirst = _names(overdue.reversed.toList());

    test('in backlog the due cards come earliest due first, equal due times in the order read', () {
      final tied = textCard('tied', createdAt: _now);
      final states = {
        ...overdueStates,
        tied.id: overdueStates[overdue.last.id]!,
      };
      final selected = selectQueue(
        [...latestFirst, tied, ...fresh],
        states,
        _today,
      );

      expect(selected.backlog, isTrue);
      expect(_names(selected.cards), [
        earliestFirst.first,
        'tied',
        ...earliestFirst.skip(1),
      ]);
      // An all-zero source keeps that order.
      expect(_names(orderQueue(selected, FirstDraw())), _names(selected.cards));
    });

    test('in backlog each run of ten keeps its place in the order and is shuffled within', () {
      expect(backlogBucketSize, 10);
      final selected = selectQueue(latestFirst, overdueStates, _today);
      final runs = [
        for (var start = 0; start < 30; start += 10)
          earliestFirst.sublist(start, start + 10).toSet(),
      ];
      final orders = <String>{};
      for (var seed = 0; seed < 50; seed++) {
        final ordered = _names(orderQueue(selected, Random(seed)));
        for (final (index, run) in runs.indexed) {
          expect(
            ordered.sublist(index * 10, index * 10 + 10).toSet(),
            run,
            reason: 'seed $seed: $ordered',
          );
        }
        orders.add(ordered.join(','));
      }
      // Control: the runs are shuffled, not kept in the order selected.
      expect(orders.length, 50);
    });

    test('an up-to-date collection is shuffled as a whole, not in runs', () {
      // Thirty cards due daily: thirty due against a load of thirty.
      final states = {
        for (final card in overdue) card.id: _dueAfter(_now, days: 1),
      };
      final selected = selectQueue([...overdue, ...fresh], states, _today);

      expect(selected.backlog, isFalse);
      expect(selected.cards, hasLength(32));
      final firsts = <String>{
        for (var seed = 0; seed < 200; seed++)
          _names(orderQueue(selected, Random(seed))).first,
      };
      // Cards from past the first run of ten, new ones included, come first.
      expect(
        firsts.difference(_names(selected.cards.take(10).toList()).toSet()),
        isNotEmpty,
      );
      expect(firsts, containsAll(['new0', 'new1']));
    });
  });

  group('study day', () {
    /// Seoul, nine hours ahead of UTC all year.
    Duration seoul(DateTime _) => const Duration(hours: 9);

    /// Los Angeles in October, seven hours behind UTC.
    Duration losAngeles(DateTime _) => const Duration(hours: -7);

    test(
      'a study day starts at 04:00 local time: 03:59 belongs to the day before',
      () {
        expect(studyDayStartHour, 4);
        // 03:59 and 04:00 on 15 October in Seoul.
        final before = DateTime.utc(2026, 10, 14, 18, 59);
        final at = DateTime.utc(2026, 10, 14, 19);

        expect(studyDayStart(before, seoul), DateTime.utc(2026, 10, 13, 19));
        expect(studyDayStart(at, seoul), at);
        // Control: in UTC both instants fall in the day that began at 04:00
        // UTC on the 14th.
        expect(studyDayStart(before, _utc), DateTime.utc(2026, 10, 14, 4));
        expect(studyDayStart(at, _utc), DateTime.utc(2026, 10, 14, 4));
      },
    );

    test(
      'a day across a change of offset runs from 04:00 to 04:00 local time',
      () {
        // Clocks go back from UTC-7 to UTC-8 at 09:00 UTC on 1 November.
        Duration pacific(DateTime instant) =>
            instant.isBefore(DateTime.utc(2026, 11, 1, 9))
            ? const Duration(hours: -7)
            : const Duration(hours: -8);
        // 02:00 PST on 1 November, still in the day of 31 October.
        final day = StudyDay.at(
          DateTime.utc(2026, 11, 1, 10),
          firstAnswers: const {},
          newCards: _quota,
          offsetAt: pacific,
        );

        expect(day.start, DateTime.utc(2026, 10, 31, 11), reason: '04:00 PDT');
        expect(day.end, DateTime.utc(2026, 11, 1, 12), reason: '04:00 PST');
      },
    );

    test('the day takes its new cards less those first answered in it across every deck, counting 04:00 and not 03:59', () async {
      final decks = await _Decks.open();
      for (var index = 0; index < _storedQuota + 10; index++) {
        await decks.add('a', 'a new $index');
      }
      // Seoul, 11:00 on 15 October; the day began at 19:00 UTC on the 14th.
      final now = DateTime.utc(2026, 10, 15, 2);
      await decks.firstAnswer(
        'a',
        'a at 04:00',
        DateTime.utc(2026, 10, 14, 19),
      );
      await decks.firstAnswer('b', 'b at 09:00', DateTime.utc(2026, 10, 15));
      await decks.firstAnswer(
        'b',
        'b at 03:59',
        DateTime.utc(2026, 10, 14, 18, 59),
      );

      final day = await decks.day(now, seoul);
      expect(day.newCardsLeft, _storedQuota - 2);
      // Deck b's answer counts against deck a's new cards.
      final queue = await decks.queueIn(['a'], day);
      expect(queue, hasLength(_storedQuota - 2));
      expect(queue, everyElement(startsWith('a new')));
    });

    test('the same answers count against the day in one time zone and not in another', () async {
      final decks = await _Decks.open();
      // 03:30 on 15 October in Seoul, 11:30 on 14 October in Los Angeles.
      final at = DateTime.utc(2026, 10, 14, 18, 30);
      await decks.firstAnswer('a', 'a answered', at);
      // 11:00 in Seoul, 19:00 the day before in Los Angeles.
      final now = DateTime.utc(2026, 10, 15, 2);

      expect((await decks.day(now, seoul)).newCardsLeft, _storedQuota);
      expect((await decks.day(now, losAngeles)).newCardsLeft, _storedQuota - 1);
    });

    test('an unused quota is not carried to the next day, and new cards answered the day before do not count', () async {
      final decks = await _Decks.open();
      for (var index = 0; index < 50; index++) {
        await decks.add('a', 'a new $index');
      }
      final yesterday = DateTime.utc(2026, 10, 13, 9);
      for (var index = 0; index < 5; index++) {
        await decks.firstAnswer('b', 'b $index', yesterday);
      }

      final day = await decks.day(_now, _utc);
      expect(day.newCardsLeft, _storedQuota);
      expect(await decks.queueIn(['a'], day), hasLength(_storedQuota));
      // The day itself counts only its own first answers, whatever it is given.
      final given = StudyDay.at(
        _now,
        firstAnswers: {
          for (var index = 0; index < 5; index++) CardId('y$index'): yesterday,
        },
        newCards: _quota,
        offsetAt: _utc,
      );
      expect(given.newCardsLeft, 20);
    });

    test('the cards left never go below zero once more new cards were answered than the day takes', () async {
      final decks = await _Decks.open();
      await decks.add('a', 'a new');
      final morning = DateTime.utc(2026, 10, 14, 5);
      for (var index = 0; index < _storedQuota + 5; index++) {
        await decks.firstAnswer('b', 'b $index', morning);
      }

      final day = await decks.day(_now, _utc);
      expect(day.newCardsLeft, 0);
      expect(await decks.queueIn(['a'], day), isEmpty);
      // Control: with 19 answered, one new card is left.
      final fewer = StudyDay.at(
        _now,
        firstAnswers: {
          for (var index = 0; index < 19; index++) CardId('m$index'): morning,
        },
        newCards: _quota,
        offsetAt: _utc,
      );
      expect(fewer.newCardsLeft, 1);
      expect(await decks.queueIn(['a'], fewer), ['a new']);
    });

    test('a backlog still pauses new cards while the day has some left', () {
      // Ten cards due every four days, all due: ten against a load of 2.5.
      final cards = [
        for (var index = 0; index < 10; index++)
          textCard('due$index', createdAt: _now),
      ];
      final fresh = textCard('new', createdAt: _now);
      final states = {
        for (final card in cards) card.id: _dueAfter(_now, days: 4),
      };

      expect(_today.newCardsLeft, 20);
      final paused = selectQueue([...cards, fresh], states, _today);
      expect(paused.backlog, isTrue);
      expect(_names(paused.cards), isNot(contains('new')));
      // Control: with two of them due the day takes the new card.
      final current = selectQueue(
        [...cards, fresh],
        {
          for (final (index, card) in cards.indexed)
            card.id: _dueAfter(
              index < 2 ? _now : _now.add(const Duration(days: 2)),
              days: 4,
            ),
        },
        _today,
      );
      expect(_names(current.cards), contains('new'));
    });

    test('the streak walks the stored answers back one study day at a time from the day before, then counts the session\'s days', () async {
      final decks = await _Decks.open();
      DateTime day(int date, [int hour = 12]) =>
          DateTime.utc(2026, 10, date, hour);
      for (final (index, at) in [day(13), day(12, 5), day(10)].indexed) {
        await decks.firstAnswer('a', 'stored $index', at);
      }
      final today = studyDayStart(day(14, 20), _utc);

      final before = await studyDaysBefore(
        today,
        decks.study.latestAnswerBefore,
        _utc,
      );

      expect(before, 2);
      int count(List<DateTime> answers, DateTime now) => streak(
        answers,
        now,
        since: today,
        daysBefore: before,
        offsetAt: _utc,
      );
      expect(count([day(14)], day(14, 20)), 3);
      // Today not yet studied: the run up to yesterday still stands.
      expect(count(const [], day(14, 20)), 2);
      // A session past 04:00 the next day counts both of its days.
      expect(count([day(14), day(15, 5)], day(15, 6)), 4);
      // Control: a day of the session without an answer ends the run there.
      expect(count([day(15, 5)], day(15, 6)), 1);
      // Control: a day with no answer before today ends the walk.
      expect(
        await studyDaysBefore(
          studyDayStart(day(16), _utc),
          decks.study.latestAnswerBefore,
          _utc,
        ),
        0,
      );
    });

    test('the walk counts 03:59 for the day before and 04:00 for its own day, in Seoul and across a change of offset', () async {
      Future<int> daysBefore(
        DateTime answer,
        DateTime now,
        UtcOffsetAt offsetAt,
      ) async {
        final decks = await _Decks.open();
        await decks.firstAnswer('a', 'answered', answer);
        return studyDaysBefore(
          studyDayStart(now, offsetAt),
          decks.study.latestAnswerBefore,
          offsetAt,
        );
      }

      // 11:00 on 15 October in Seoul; 03:59 and 04:00 that morning.
      final seoulNow = DateTime.utc(2026, 10, 15, 2);
      expect(
        await daysBefore(DateTime.utc(2026, 10, 14, 18, 59), seoulNow, seoul),
        1,
      );
      expect(
        await daysBefore(DateTime.utc(2026, 10, 14, 19), seoulNow, seoul),
        0,
      );
      // Clocks go back from UTC-7 to UTC-8 at 09:00 UTC on 1 November, so
      // 31 October runs 25 hours, from 11:00 UTC to 12:00 UTC the next day.
      Duration pacific(DateTime instant) =>
          instant.isBefore(DateTime.utc(2026, 11, 1, 9))
          ? const Duration(hours: -7)
          : const Duration(hours: -8);
      final pacificNow = DateTime.utc(2026, 11, 1, 20);
      // 03:30 PST on 1 November, past a fixed 24 hours, is in 31 October.
      expect(
        await daysBefore(
          DateTime.utc(2026, 11, 1, 11, 30),
          pacificNow,
          pacific,
        ),
        1,
      );
      // 04:00 PDT on 31 October starts it; 03:59 PDT is in 30 October.
      expect(
        await daysBefore(DateTime.utc(2026, 10, 31, 11), pacificNow, pacific),
        1,
      );
      expect(
        await daysBefore(
          DateTime.utc(2026, 10, 31, 10, 59),
          pacificNow,
          pacific,
        ),
        0,
      );
    });
  });
}
