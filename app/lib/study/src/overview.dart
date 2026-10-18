import 'dart:math';

import '../../deck/deck.dart';
import 'model.dart';
import 'queue.dart';
import 'today.dart';

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

  /// The goal of a study day from its [plan], as today's list places the
  /// cards: those done, answered "Know" last today, and those left, the
  /// selection and the cards still on "Don't know". A card answered "Don't
  /// know" is left until it is answered "Know".
  factory DailyGoal.of(DayPlan plan) =>
      DailyGoal(done: plan.done.length, goal: plan.done.length + plan.left);

  final int done;
  final int goal;

  /// Whether every card of the goal is done, and there was one.
  bool get reached => goal > 0 && done == goal;
}

/// Where the user stands today, which the today card states in place of the
/// goal's numbers, which its ring shows. It states where the user is and
/// never what to tap.
sealed class TodayStatus {
  const TodayStatus();

  /// The first status that holds for [goal] with a [streak] of study days:
  /// nothing done yet with a streak of two days or more; nothing done yet;
  /// three cards or fewer left; half of the goal or more done; some done.
  factory TodayStatus.of(DailyGoal goal, {required int streak}) {
    final left = goal.goal - goal.done;
    if (goal.done == 0) {
      return streak >= 2 ? StatusStreak(streak) : const StatusWaiting();
    }
    if (left <= 3) return const StatusAlmostDone();
    if (goal.done * 2 >= goal.goal) return const StatusPastHalf();
    return const StatusStarted();
  }
}

/// Nothing done today yet, on a streak of [days] study days.
final class StatusStreak extends TodayStatus {
  const StatusStreak(this.days);

  final int days;

  @override
  bool operator ==(Object other) => other is StatusStreak && other.days == days;

  @override
  int get hashCode => days.hashCode;
}

/// Nothing done today yet.
final class StatusWaiting extends TodayStatus {
  const StatusWaiting();
}

/// Some done, and three cards or fewer left.
final class StatusAlmostDone extends TodayStatus {
  const StatusAlmostDone();
}

/// Half of the goal or more done.
final class StatusPastHalf extends TodayStatus {
  const StatusPastHalf();
}

/// Some done, under half of the goal.
final class StatusStarted extends TodayStatus {
  const StatusStarted();
}

/// The overdue reviews left at the start of each of the [forecastDays] study
/// days from today, when [backlog] are overdue today and the user clears
/// [perDay] of them a day: the catch-up a backlog card projects.
List<int> catchUp(int backlog, int perDay) => [
  for (var day = 0; day < forecastDays; day++) max(0, backlog - day * perDay),
];
