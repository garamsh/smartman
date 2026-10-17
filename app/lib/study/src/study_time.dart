import 'dart:math';

import '../../deck/deck.dart' show CardId;
import 'model.dart';
import 'queue.dart';
import 'study_repository.dart';

/// One study day's answers, each counted up to [answerCapMs]: the time and
/// number of the answers that were not their card's first, and of those that
/// were.
typedef StudyDayTotal = ({
  int reviewMs,
  int reviews,
  int firstMs,
  int firstAnswers,
});

/// How long the user takes over one answer, in milliseconds: a review, and a
/// card's first answer.
final class Pace {
  const Pace({required this.reviewMs, required this.firstMs});

  /// The pace while the user's own is unknown: [defaultAnswerMs] for both.
  static const unknown = Pace(
    reviewMs: defaultAnswerMs,
    firstMs: defaultAnswerMs,
  );

  final int reviewMs;
  final int firstMs;

  /// The whole minutes [reviews] reviews and [fresh] new cards take, rounded
  /// up.
  int minutes({required int reviews, required int fresh}) =>
      ((reviews * reviewMs + fresh * firstMs) / 60000).ceil();

  @override
  bool operator ==(Object other) =>
      other is Pace && other.reviewMs == reviewMs && other.firstMs == firstMs;

  @override
  int get hashCode => Object.hash(reviewMs, firstMs);

  @override
  String toString() => 'Pace(review: $reviewMs ms, first: $firstMs ms)';
}

/// The time the user studies on a study day, in whole milliseconds, from
/// [days], the study days of the window, oldest first.
///
/// Each day's estimate is the mean of the days up to it, each weighted
/// 0.5^(age / [studyTimeHalfLife]) with the age in study days, held within
/// [studyTimeStepPercent] of the day before's; the last is returned.
int studyTime(List<StudyDayTotal> days) {
  double? time;
  for (var upto = 0; upto < days.length; upto++) {
    var sum = 0.0;
    var weights = 0.0;
    for (var index = 0; index <= upto; index++) {
      final weight = pow(0.5, (upto - index) / studyTimeHalfLife).toDouble();
      final day = days[index];
      sum += weight * (day.reviewMs + day.firstMs);
      weights += weight;
    }
    final next = sum / weights;
    final step = studyTimeStepPercent / 100;
    time = switch (time) {
      null => next,
      final before => next.clamp(before * (1 - step), before * (1 + step)),
    };
  }
  return (time ?? 0).round();
}

/// The user's [Pace] over [days], the study days of the window, oldest first:
/// for each kind, the time of its answers over their number, each day
/// weighted 0.5^(age / [paceHalfLife]), in whole milliseconds; or
/// [defaultAnswerMs] for a kind with fewer than [paceMinimum] answers.
Pace paceOf(List<StudyDayTotal> days) {
  int kind(int Function(StudyDayTotal) ms, int Function(StudyDayTotal) n) {
    var time = 0.0;
    var answers = 0.0;
    var count = 0;
    for (final (index, day) in days.indexed) {
      final weight = pow(0.5, (days.length - 1 - index) / paceHalfLife);
      time += weight * ms(day);
      answers += weight * n(day);
      count += n(day);
    }
    return count < paceMinimum ? defaultAnswerMs : (time / answers).round();
  }

  return Pace(
    reviewMs: kind((day) => day.reviewMs, (day) => day.reviews),
    firstMs: kind((day) => day.firstMs, (day) => day.firstAnswers),
  );
}

/// How many new cards a study day takes, across every deck, from [days], the
/// study days of the window before it, oldest first; [due], the reviews due
/// in it when it started; and [load], the collection's [dailyLoad] then.
///
/// While [days] holds fewer than [coldStartStudyDays], [coldStartNewCards].
/// Otherwise the [studyTime] left after the reviews set aside, at the review
/// pace in whole milliseconds, divided by the first-answer pace, rounded down,
/// never below zero.
/// The reviews set aside are [load], with the reviews due beyond it spread
/// over [reviewSpreadDays].
int dailyNewCards(
  List<StudyDayTotal> days, {
  required int due,
  required double load,
}) {
  if (days.length < coldStartStudyDays) return coldStartNewCards;
  final pace = paceOf(days);
  final setAside = load + max(0, due - load) / reviewSpreadDays;
  final left = studyTime(days) - (setAside * pace.reviewMs).round();
  return max(0, left ~/ pace.firstMs);
}

/// [answers] by study day in the zone [offsetAt] gives, oldest first, each
/// answer counted up to [answerCapMs]. A day without an answer has no total.
List<StudyDayTotal> totalsOf(
  Iterable<TimedAnswer> answers, [
  UtcOffsetAt offsetAt = localOffsetAt,
]) {
  final byDay = <DateTime, StudyDayTotal>{};
  for (final answer in answers) {
    final day = studyDayStart(answer.at, offsetAt);
    final ms = min(answer.duration.inMilliseconds, answerCapMs);
    final total =
        byDay[day] ?? (reviewMs: 0, reviews: 0, firstMs: 0, firstAnswers: 0);
    byDay[day] = answer.first
        ? (
            reviewMs: total.reviewMs,
            reviews: total.reviews,
            firstMs: total.firstMs + ms,
            firstAnswers: total.firstAnswers + 1,
          )
        : (
            reviewMs: total.reviewMs + ms,
            reviews: total.reviews + 1,
            firstMs: total.firstMs,
            firstAnswers: total.firstAnswers,
          );
  }
  final starts = byDay.keys.toList()..sort();
  return [for (final start in starts) byDay[start]!];
}

/// The totals of the latest [studyDayWindow] study days before [before], the
/// start of a study day, oldest first, read through [repository]: a walk back
/// one study day at a time to the window's first, then its answers.
///
/// A failed read throws the `StudyFailure` that reports it.
Future<List<StudyDayTotal>> readStudyDays(
  StudyRepository repository,
  DateTime before, [
  UtcOffsetAt offsetAt = localOffsetAt,
]) async {
  DateTime? first;
  var end = before;
  for (var day = 0; day < studyDayWindow; day++) {
    final latest = await repository.latestAnswerBefore(end);
    if (latest == null) break;
    first = end = studyDayStart(latest, offsetAt);
  }
  if (first == null) return const [];
  return totalsOf(await repository.answersBetween(first, before), offsetAt);
}

/// Today's [StudyDay] at [now] and the user's [Pace], read through
/// [repository] from the stored reviews and card states, across every deck.
///
/// The day's new cards are [dailyNewCards] as the day stood when it started,
/// so answering during it does not change them: the reviews due then are the
/// cards due before it ends that were not answered in it, and the cards
/// answered in it that had an answer before it; the daily load counts the
/// latter at the time between their last answer before the day and their
/// first in it.
///
/// A failed read throws the `StudyFailure` that reports it.
Future<(StudyDay, Pace)> readStudyDay(
  StudyRepository repository,
  DateTime now, [
  UtcOffsetAt offsetAt = localOffsetAt,
]) async {
  final start = studyDayStart(now, offsetAt);
  final end = studyDayEnd(start, offsetAt);
  final days = await readStudyDays(repository, start, offsetAt);
  final firstToday = <CardId, DateTime>{};
  for (final answer in await repository.answersSince(start)) {
    firstToday.putIfAbsent(answer.card, () => answer.at);
  }
  final earlier = await repository.latestAnswersBefore(
    firstToday.keys.toList(),
    start,
  );
  var due = 0;
  final standing = <CardState>[];
  for (final MapEntry(key: card, value: state)
      in (await repository.allStates()).entries) {
    if (firstToday.containsKey(card)) continue;
    standing.add(state);
    if (state.due.isBefore(end)) due++;
  }
  var load = dailyLoad(standing);
  for (final MapEntry(key: card, value: last) in earlier.entries) {
    due++;
    final interval =
        firstToday[card]!.difference(last).inSeconds / Duration.secondsPerDay;
    load += 1 / max(interval, 1);
  }
  final day = StudyDay.at(
    now,
    firstAnswers: [
      for (final MapEntry(key: card, value: at) in firstToday.entries)
        if (!earlier.containsKey(card)) at,
    ],
    newCards: dailyNewCards(days, due: due, load: load),
    offsetAt: offsetAt,
  );
  return (day, paceOf(days));
}
