import 'dart:math';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smartman/deck/deck.dart';
import 'package:smartman/shared/database.dart';
import 'package:smartman/study/src/model.dart';
import 'package:smartman/study/src/queue.dart';
import 'package:smartman/study/src/rust/api/engine.dart';
import 'package:smartman/study/src/study_repository.dart';

import 'fixtures.dart';

final _now = DateTime.utc(2026, 10, 14, 9);

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

  /// The fronts of the cards a session over [decks] would study now.
  Future<List<String>> queue(List<String> decks) async {
    final (read, states) = await readCards(
      DeckSelection.of([for (final deck in decks) ids[deck]!])!,
      cards,
      study,
    );
    return [
      for (final card in selectQueue(read, states, _now).cards)
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
    test('a session over several decks takes every due card in them and the 20 oldest new cards across them', () async {
      expect(newCardLimit, 20);
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
          '$deck later',
          due: _now.add(const Duration(minutes: 1)),
        );
      }

      expect(
        await decks.queue(['a', 'b', 'empty']),
        unorderedEquals([
          'a due',
          'a overdue',
          'b due',
          'b overdue',
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
      _now,
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
      final current = selectQueue([...atThreshold, ...fresh], atStates, _now);
      final paused = selectQueue([...over, ...fresh], overStates, _now);

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
        _now,
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
      final selected = selectQueue(latestFirst, overdueStates, _now);
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
      final selected = selectQueue([...overdue, ...fresh], states, _now);

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
}
