import 'dart:math';

import '../../deck/deck.dart';
import 'model.dart';
import 'study_repository.dart';

/// How many never-reviewed cards a study day takes, across all the user's
/// decks.
const newCardLimit = 20;

/// The local hour a study day starts at.
const studyDayStartHour = 4;

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

/// The decks are in backlog when more than this many days of reviews are due:
/// the due count against this multiple of [dailyLoad].
const backlogDays = 3;

/// How many consecutive cards of a backlog's order are shuffled together.
const backlogBucketSize = 10;

/// The offset from UTC of the device's time zone at [instant].
typedef UtcOffsetAt = Duration Function(DateTime instant);

/// The offset of the time zone the device is in now.
Duration localOffsetAt(DateTime instant) => instant.toLocal().timeZoneOffset;

/// When the study day holding [now] started: the latest [studyDayStartHour]
/// o'clock at or before it, in the time zone [offsetAt] gives.
DateTime studyDayStart(DateTime now, [UtcOffsetAt offsetAt = localOffsetAt]) {
  final wall = now.toUtc().add(offsetAt(now));
  final date = DateTime.utc(wall.year, wall.month, wall.day);
  return wall.hour < studyDayStartHour
      ? _startOn(DateTime.utc(date.year, date.month, date.day - 1), offsetAt)
      : _startOn(date, offsetAt);
}

/// The [studyDayStartHour] o'clock of the calendar [date] in the time zone
/// [offsetAt] gives, read again at the instant it names so that a change of
/// offset between [date]'s midnight and then is applied.
DateTime _startOn(DateTime date, UtcOffsetAt offsetAt) {
  final wall = DateTime.utc(date.year, date.month, date.day, studyDayStartHour);
  return wall.subtract(offsetAt(wall.subtract(offsetAt(wall))));
}

/// Today's study day as the queue reads it.
final class StudyDay {
  const StudyDay({
    required this.start,
    required this.end,
    required this.newCardsLeft,
  });

  /// The study day holding [now], in which the user first answered a card
  /// at each of [firstAnswers], across every deck.
  factory StudyDay.at(
    DateTime now, {
    required Iterable<DateTime> firstAnswers,
    UtcOffsetAt offsetAt = localOffsetAt,
  }) {
    final start = studyDayStart(now, offsetAt);
    final wall = start.toUtc().add(offsetAt(start));
    final end = _startOn(
      DateTime.utc(wall.year, wall.month, wall.day + 1),
      offsetAt,
    );
    final taken = firstAnswers
        .where((answer) => !answer.isBefore(start) && answer.isBefore(end))
        .length;
    return StudyDay(
      start: start,
      end: end,
      newCardsLeft: max(0, newCardLimit - taken),
    );
  }

  final DateTime start;

  /// When the next study day starts.
  final DateTime end;

  /// How many new cards the day still takes: [newCardLimit] less the cards
  /// first answered in it, never below zero.
  final int newCardsLeft;

  /// Whether a card due at [due] is due by the end of this day.
  bool holds(DateTime due) => due.isBefore(end);
}

/// The cards a session studies, as [selectQueue] selects them.
final class SelectedQueue {
  /// Every due card, then as many new ones as the day has left, oldest
  /// first.
  const SelectedQueue.current(this.cards) : backlog = false;

  /// Every due card, earliest due first, and no new card.
  const SelectedQueue.backlog(this.cards) : backlog = true;

  final List<Card> cards;

  /// Whether the decks are in backlog, so new cards pause.
  final bool backlog;
}

/// The reviews a day [states] ask for at their current intervals: the sum,
/// over every reviewed card, of one over its interval in days, at least one.
double dailyLoad(Iterable<CardState> states) {
  var load = 0.0;
  for (final state in states) {
    final days =
        state.due.difference(state.lastReview).inSeconds /
        Duration.secondsPerDay;
    load += 1 / max(days, 1);
  }
  return load;
}

/// The cards a session in [day] studies, from [cards] and the stored [states]
/// of those reviewed. A card is due when it falls due before [day] ends.
///
/// The cards are in backlog when more than [backlogDays] of [dailyLoad] are
/// due. In backlog the session takes every due card, earliest due first, ties
/// in the order read, and no new card. Otherwise it takes every due card, then
/// as many cards with no state as [day] has left, oldest first by creation
/// time.
SelectedQueue selectQueue(
  List<Card> cards,
  Map<CardId, CardState> states,
  StudyDay day,
) {
  final due = <({int position, Card card, DateTime due})>[];
  final fresh = <({int position, Card card})>[];
  final reviewed = <CardState>[];
  for (final (position, card) in cards.indexed) {
    final state = states[card.id];
    if (state == null) {
      fresh.add((position: position, card: card));
      continue;
    }
    reviewed.add(state);
    if (day.holds(state.due)) {
      due.add((position: position, card: card, due: state.due));
    }
  }
  if (due.length > backlogDays * dailyLoad(reviewed)) {
    // List.sort is not stable, so equal due times keep the order read.
    due.sort((a, b) {
      final byDue = a.due.compareTo(b.due);
      return byDue != 0 ? byDue : a.position.compareTo(b.position);
    });
    return SelectedQueue.backlog([for (final entry in due) entry.card]);
  }
  fresh.sort((a, b) {
    final byAge = a.card.createdAt.compareTo(b.card.createdAt);
    return byAge != 0 ? byAge : a.position.compareTo(b.position);
  });
  return SelectedQueue.current([
    for (final entry in due) entry.card,
    for (final entry in fresh.take(day.newCardsLeft)) entry.card,
  ]);
}

/// [queue]'s cards in an order drawn from [random].
///
/// In backlog, each run of [backlogBucketSize] consecutive cards is shuffled
/// in its place, so earlier due cards still come first. Otherwise every order
/// is equally likely: the due cards shuffled, with each new card at a random
/// place among them.
///
/// Each draw picks the card for the next place from those of its run not yet
/// placed, the first of them on a draw of 0, so an all-zero [random] keeps
/// [queue]'s order.
List<Card> orderQueue(SelectedQueue queue, Random random) {
  final ordered = List.of(queue.cards);
  final run = queue.backlog ? backlogBucketSize : max(ordered.length, 1);
  for (var start = 0; start < ordered.length; start += run) {
    final end = min(start + run, ordered.length);
    for (var place = start; place < end - 1; place++) {
      final pick = place + random.nextInt(end - place);
      final card = ordered[pick];
      ordered[pick] = ordered[place];
      ordered[place] = card;
    }
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

/// How many study days in a row hold one of [answers]: counted back from the
/// day holding [now] when it holds one, otherwise from the day before, so a
/// day not yet studied breaks nothing until it ends.
int streak(
  Iterable<DateTime> answers,
  DateTime now, [
  UtcOffsetAt offsetAt = localOffsetAt,
]) {
  final days = {for (final answer in answers) studyDayStart(answer, offsetAt)};
  DateTime before(DateTime day) =>
      studyDayStart(day.subtract(const Duration(seconds: 1)), offsetAt);
  var day = studyDayStart(now, offsetAt);
  if (!days.contains(day)) day = before(day);
  var count = 0;
  while (days.contains(day)) {
    count++;
    day = before(day);
  }
  return count;
}
