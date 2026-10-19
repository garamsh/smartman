import { defaultAnswerMs, paceHalfLife, paceMinimum, studyDayEnd } from "./queue";

// The day's new cards from the user's daily study minutes and pace, by the rules of study.md, as
// app/lib/study/src/study_time.dart computes them.

/**
 * One study day's answers, each counted up to `answerCapMs`: the time and number of the answers
 * that were not their card's first, and of those that were.
 */
export type StudyDayTotal = {
  reviewMs: number;
  reviews: number;
  firstMs: number;
  firstAnswers: number;
};

/** How long the user takes over one answer, in whole milliseconds: a review, and a first answer. */
export type Pace = { reviewMs: number; firstMs: number };

/** The pace while the user's own is unknown: `defaultAnswerMs` for both. */
export const unknownPace: Pace = { reviewMs: defaultAnswerMs, firstMs: defaultAnswerMs };

/**
 * The user's pace over [days], the study days of the window, oldest first: for each kind, the
 * time of its answers over their number, each day weighted 0.5^(age / `paceHalfLife`), in whole
 * milliseconds; or `defaultAnswerMs` for a kind with fewer than `paceMinimum` answers.
 */
export function paceOf(days: readonly StudyDayTotal[]): Pace {
  const kind = (ms: (day: StudyDayTotal) => number, n: (day: StudyDayTotal) => number) => {
    let time = 0;
    let answers = 0;
    let count = 0;
    days.forEach((day, index) => {
      const weight = 0.5 ** ((days.length - 1 - index) / paceHalfLife);
      time += weight * ms(day);
      answers += weight * n(day);
      count += n(day);
    });
    return count < paceMinimum ? defaultAnswerMs : Math.round(time / answers);
  };
  return {
    reviewMs: kind(
      (day) => day.reviewMs,
      (day) => day.reviews,
    ),
    firstMs: kind(
      (day) => day.firstMs,
      (day) => day.firstAnswers,
    ),
  };
}

/**
 * How many new cards a study day takes, across every deck: the [minutes] the user studies a day,
 * less the [due] reviews at the review pace of [pace], in whole milliseconds, divided by its
 * first-answer pace, rounded down, never below zero (ADR 0085).
 */
export function dailyNewCards({
  minutes,
  due,
  pace,
}: {
  minutes: number;
  due: number;
  pace: Pace;
}): number {
  return Math.max(0, Math.trunc((minutes * 60_000 - due * pace.reviewMs) / pace.firstMs));
}

/**
 * The start of the study day on which the last of [remaining] never-reviewed cards is first
 * answered, when the day starting [todayStart] takes [today] more of them and every later day
 * [perDay]; null when they are never all taken, with [perDay] zero and more left than today takes.
 */
export function lastNewCardDay({
  remaining,
  today,
  perDay,
  todayStart,
  timeZone,
}: {
  remaining: number;
  today: number;
  perDay: number;
  todayStart: number;
  timeZone: string;
}): number | null {
  if (remaining <= today) return todayStart;
  if (perDay <= 0) return null;
  let start = todayStart;
  for (let left = remaining - today; left > 0; left -= perDay) {
    start = studyDayEnd(start, timeZone);
  }
  return start;
}

/**
 * What a choice of daily study minutes means, across every deck: the reviews [due] as today stood
 * when it started, the cards [started] in it, the [unstarted] cards never answered, at the user's
 * [pace], whether new cards pause for a [backlog], and the start of today, [todayStart].
 */
export type MinutesPlan = {
  due: number;
  started: number;
  unstarted: number;
  backlog: boolean;
  pace: Pace;
  todayStart: number;
  timeZone: string;
};

/**
 * At [minutes] a day by [plan]: the new cards left today, and the start of the study day on which
 * the last unstarted card is first answered, null when none is left or they are never all taken.
 * In a backlog no new card is taken.
 */
export function minutesPreview(
  plan: MinutesPlan,
  minutes: number,
): { fresh: number; lastDay: number | null } {
  if (plan.backlog) return { fresh: 0, lastDay: null };
  const perDay = dailyNewCards({ minutes, due: plan.due, pace: plan.pace });
  const fresh = Math.min(plan.unstarted, Math.max(0, perDay - plan.started));
  return {
    fresh,
    lastDay:
      plan.unstarted === 0
        ? null
        : lastNewCardDay({
            remaining: plan.unstarted,
            today: fresh,
            perDay,
            todayStart: plan.todayStart,
            timeZone: plan.timeZone,
          }),
  };
}

/** The whole minutes [reviews] reviews and [fresh] new cards take at [pace], rounded up. */
export function sessionMinutes(reviews: number, fresh: number, pace: Pace): number {
  return Math.ceil((reviews * pace.reviewMs + fresh * pace.firstMs) / 60_000);
}
