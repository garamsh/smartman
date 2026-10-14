import 'package:flutter_test/flutter_test.dart';
import 'package:smartman/deck/deck.dart';
import 'package:smartman/study/src/queue.dart';

import 'fixtures.dart';

void main() {
  final now = DateTime.utc(2026, 10, 14, 9);
  List<String> names(List<Card> cards) => [
    for (final card in cards) card.id.value,
  ];

  test('due cards come first, earliest due first, and cards due later are left out', () {
    final cards = [
      for (final (index, name) in [
        'hour',
        'week',
        'now',
        'later',
        'new',
      ].indexed)
        textCard(name, createdAt: now.subtract(Duration(days: 30 - index))),
    ];
    final states = {
      const CardId('hour'): dueAt(now.subtract(const Duration(hours: 1))),
      const CardId('week'): dueAt(now.subtract(const Duration(days: 7))),
      const CardId('now'): dueAt(now),
      const CardId('later'): dueAt(now.add(const Duration(minutes: 1))),
    };

    expect(names(buildQueue(cards, states, now)), [
      'week',
      'hour',
      'now',
      'new',
    ]);
  });

  test('cards due at the same time keep the deck order', () {
    final cards = [
      for (final name in ['b', 'a', 'c'])
        textCard(name, createdAt: now.subtract(const Duration(days: 1))),
    ];
    final states = {for (final card in cards) card.id: dueAt(now)};

    expect(names(buildQueue(cards, states, now)), ['b', 'a', 'c']);
  });

  test('a session takes the 20 oldest new cards after every due card', () {
    expect(newCardLimit, 20);
    final fresh = [
      for (var index = 0; index < 25; index++)
        textCard(
          'new$index',
          createdAt: now.subtract(Duration(days: 25 - index)),
        ),
    ];
    final due = [
      for (var index = 0; index < 22; index++)
        textCard(
          'due$index',
          createdAt: now.subtract(Duration(days: 60 - index)),
        ),
    ];
    final states = {
      for (final (index, card) in due.indexed)
        card.id: dueAt(now.subtract(Duration(hours: 22 - index))),
    };

    final queue = names(buildQueue([...due, ...fresh], states, now));

    expect(queue, [
      for (var index = 0; index < 22; index++) 'due$index',
      for (var index = 0; index < 20; index++) 'new$index',
    ]);
  });

  test('a deck with nothing due and no new card has an empty queue', () {
    final cards = [textCard('later', createdAt: now)];
    final states = {cards.single.id: dueAt(now.add(const Duration(days: 1)))};

    expect(buildQueue(cards, states, now), isEmpty);
    expect(buildQueue(const [], const {}, now), isEmpty);
  });

  test('a card put back comes after reshowGap other cards, or after all that remain', () {
    expect(reshowGap, 3);
    final cards = [
      for (final name in ['a', 'b', 'c', 'd', 'e', 'x'])
        textCard(name, createdAt: now),
    ];
    final again = cards.last;

    final long = cards.sublist(0, 5);
    reinsert(long, again);
    expect(names(long), ['a', 'b', 'c', 'x', 'd', 'e']);

    final short = cards.sublist(0, 1);
    reinsert(short, again);
    expect(names(short), ['a', 'x']);

    final empty = <Card>[];
    reinsert(empty, again);
    expect(names(empty), ['x']);
  });
}
