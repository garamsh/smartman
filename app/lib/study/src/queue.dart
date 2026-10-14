import 'dart:math';

import '../../deck/deck.dart';
import 'model.dart';
import 'study_repository.dart';

/// How many never-reviewed cards one session takes, across all its decks.
const newCardLimit = 20;

/// The fewest other cards shown before a "Don't know" card comes back.
const reshowGapMin = 3;

/// The most other cards shown before a "Don't know" card comes back.
const reshowGapMax = 5;

/// The cards of every deck in [decks], read through [cards], and the stored
/// state of each one reviewed.
///
/// A failed read throws the [DeckFailure] or `StudyFailure` that reports it.
Future<(List<Card>, Map<CardId, CardState>)> readCards(
  DeckSelection decks,
  DeckRepository cards,
  StudyRepository repository,
) async {
  final read = [for (final deck in decks.ids) ...await cards.listCards(deck)];
  final states = await repository.statesOf([for (final card in read) card.id]);
  return (read, states);
}

/// The cards a session starting at [now] studies, from [cards] and the stored
/// [states] of those reviewed: every card due at or before [now], then up to
/// [newCardLimit] cards with no state, oldest first by creation time.
List<Card> selectQueue(
  List<Card> cards,
  Map<CardId, CardState> states,
  DateTime now,
) {
  final due = <Card>[];
  final fresh = <({int position, Card card})>[];
  for (final (position, card) in cards.indexed) {
    final state = states[card.id];
    if (state == null) {
      fresh.add((position: position, card: card));
    } else if (!state.due.isAfter(now)) {
      due.add(card);
    }
  }
  // List.sort is not stable, so equal creation times keep the order read.
  fresh.sort((a, b) {
    final byAge = a.card.createdAt.compareTo(b.card.createdAt);
    return byAge != 0 ? byAge : a.position.compareTo(b.position);
  });
  return [...due, for (final entry in fresh.take(newCardLimit)) entry.card];
}

/// [queue] in an order drawn from [random], every order equally likely: the
/// due cards shuffled, with each new card at a random place among them.
///
/// Each draw picks the card for the next place from those not yet placed, the
/// first of them on a draw of 0, so an all-zero [random] keeps [queue]'s order.
List<Card> orderQueue(List<Card> queue, Random random) {
  final ordered = List.of(queue);
  for (var place = 0; place < ordered.length - 1; place++) {
    final pick = place + random.nextInt(ordered.length - place);
    final card = ordered[pick];
    ordered[pick] = ordered[place];
    ordered[place] = card;
  }
  return ordered;
}

/// Puts [card] back into [queue], the cards still to show with the next one
/// first, so that a gap drawn from [random] between [reshowGapMin] and
/// [reshowGapMax] other cards come before it, or as many as remain.
void reinsert(List<Card> queue, Card card, Random random) {
  final gap = reshowGapMin + random.nextInt(reshowGapMax - reshowGapMin + 1);
  queue.insert(min(gap, queue.length), card);
}
