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

/// How many new cards a study day takes, across every deck: the [minutes] the
/// user studies a day, less the [due] reviews at the review pace of [pace], in
/// whole milliseconds, divided by its first-answer pace, rounded down, never
/// below zero (ADR 0085).
int dailyNewCards({
  required int minutes,
  required int due,
  required Pace pace,
}) => max(0, (minutes * 60000 - due * pace.reviewMs) ~/ pace.firstMs);

/// The study day on which the last of [remaining] never-reviewed cards is
/// first answered, as its start, when the day starting [todayStart] takes
/// [today] more of them and every later day [perDay]; null when they are never
/// all taken, with [perDay] zero and more left than today takes.
DateTime? lastNewCardDay({
  required int remaining,
  required int today,
  required int perDay,
  required DateTime todayStart,
  UtcOffsetAt offsetAt = localOffsetAt,
}) {
  if (remaining <= today) return todayStart;
  if (perDay <= 0) return null;
  var day = todayStart;
  for (var left = remaining - today; left > 0; left -= perDay) {
    day = studyDayEnd(day, offsetAt);
  }
  return day;
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
/// [repository] from the stored reviews, card states and daily study minutes,
/// across every deck.
///
/// The day's new cards are [dailyNewCards] over the reviews due as the day
/// stood when it started, so answering during it does not change them: the
/// cards due before it ends that were not answered in it, and the cards
/// answered in it that had an answer before it. A change of the minutes
/// applies at once.
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
  var due = earlier.length;
  for (final MapEntry(key: card, value: state)
      in (await repository.allStates()).entries) {
    if (!firstToday.containsKey(card) && state.due.isBefore(end)) due++;
  }
  final pace = paceOf(days);
  final day = StudyDay.at(
    now,
    firstAnswers: [
      for (final MapEntry(key: card, value: at) in firstToday.entries)
        if (!earlier.containsKey(card)) at,
    ],
    newCards: dailyNewCards(
      minutes: await repository.dailyMinutes(),
      due: due,
      pace: pace,
    ),
    offsetAt: offsetAt,
  );
  return (day, pace);
}
