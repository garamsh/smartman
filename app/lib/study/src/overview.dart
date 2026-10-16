import '../../deck/deck.dart';
import 'model.dart';
import 'queue.dart';

/// The interval from which a reviewed card counts as mastered (익힘).
const masteredInterval = Duration(days: 21);

/// How far a card has come.
enum CardProgress {
  /// Reviewed, with a current interval of at least [masteredInterval] (익힘).
  mastered,

  /// Reviewed, with a shorter interval (학습 중).
  learning,

  /// Never reviewed (새 카드).
  fresh,
}

/// The progress of a card whose stored state is [state], null when it was
/// never reviewed. The current interval is the time from its last review to
/// its due time.
CardProgress progressOf(CardState? state) => switch (state) {
  null => CardProgress.fresh,
  CardState(:final lastReview, :final due)
      when due.difference(lastReview) >= masteredInterval =>
    CardProgress.mastered,
  CardState() => CardProgress.learning,
};

/// How many of a selection's cards are mastered, learning and new.
final class DeckProgress {
  const DeckProgress({
    required this.mastered,
    required this.learning,
    required this.fresh,
  });

  /// The progress of every one of [cards], from the stored [states] of those
  /// reviewed.
  factory DeckProgress.of(Iterable<Card> cards, Map<CardId, CardState> states) {
    var mastered = 0;
    var learning = 0;
    var fresh = 0;
    for (final card in cards) {
      switch (progressOf(states[card.id])) {
        case CardProgress.mastered:
          mastered++;
        case CardProgress.learning:
          learning++;
        case CardProgress.fresh:
          fresh++;
      }
    }
    return DeckProgress(mastered: mastered, learning: learning, fresh: fresh);
  }

  final int mastered;
  final int learning;
  final int fresh;

  int get total => mastered + learning + fresh;
}

/// How many study days [forecast] covers, today included.
const forecastDays = 7;

/// The cards due on each of the [forecastDays] study days from [day]: today's
/// [load], then, for each later day, the stored [states] that fall due within
/// it, in the time zone [offsetAt] gives.
List<int> forecast(
  Iterable<CardState> states,
  StudyDay day, {
  required int load,
  UtcOffsetAt offsetAt = localOffsetAt,
}) {
  final ends = <DateTime>[day.end];
  while (ends.length < forecastDays) {
    ends.add(studyDayEnd(ends.last, offsetAt));
  }
  final counts = List.filled(forecastDays, 0)..[0] = load;
  for (final state in states) {
    if (state.due.isBefore(day.end)) continue;
    final index = ends.indexWhere(state.due.isBefore);
    if (index > 0) counts[index]++;
  }
  return counts;
}

/// The daily goal: [done] of the [goal] cards the study day held.
final class DailyGoal {
  const DailyGoal({required this.done, required this.goal});

  /// The goal of the study [day] from the recorded [answers] and the cards
  /// [left] to study in it: every card answered within the day or left, each
  /// once, as the load stood when the day started; done are those no longer
  /// left. A card answered "Don't know" and due again today is left, so not
  /// yet done. Practice records nothing, so it counts toward neither.
  factory DailyGoal.of(
    Iterable<({CardId card, DateTime at})> answers,
    Iterable<CardId> left,
    StudyDay day,
  ) {
    final remaining = left.toSet();
    final goal = {
      for (final answer in answers)
        if (!answer.at.isBefore(day.start) && answer.at.isBefore(day.end))
          answer.card,
      ...remaining,
    }.length;
    return DailyGoal(done: goal - remaining.length, goal: goal);
  }

  final int done;
  final int goal;

  /// Whether every card of the goal is done, and there was one.
  bool get reached => goal > 0 && done == goal;
}
