import 'dart:math';

import '../../deck/deck.dart';
import 'model.dart';

/// How many never-reviewed cards one session takes.
const newCardLimit = 20;

/// How many other cards are shown before a "Don't know" card comes back.
const reshowGap = 3;

/// The cards a session starting at [now] studies, from a deck's [cards]
/// (oldest first) and the stored [states] of those reviewed: the cards due at
/// or before [now], earliest due first, then up to [newCardLimit] cards with
/// no state, oldest first.
List<Card> buildQueue(
  List<Card> cards,
  Map<CardId, CardState> states,
  DateTime now,
) {
  final due = <({int position, Card card, DateTime due})>[];
  final fresh = <Card>[];
  for (final (position, card) in cards.indexed) {
    final state = states[card.id];
    if (state == null) {
      fresh.add(card);
    } else if (!state.due.isAfter(now)) {
      due.add((position: position, card: card, due: state.due));
    }
  }
  // List.sort is not stable, so equal due times fall back to the deck's order.
  due.sort((a, b) {
    final byDue = a.due.compareTo(b.due);
    return byDue != 0 ? byDue : a.position.compareTo(b.position);
  });
  return [for (final entry in due) entry.card, ...fresh.take(newCardLimit)];
}

/// Puts [card] back into [queue], the cards still to show with the next one
/// first, so that [reshowGap] other cards come before it, or as many as remain.
void reinsert(List<Card> queue, Card card) =>
    queue.insert(min(reshowGap, queue.length), card);
