import {
  coldStartNewCards,
  coldStartStudyDays,
  defaultAnswerMs,
  paceHalfLife,
  paceMinimum,
  reviewSpreadDays,
  studyTimeHalfLife,
  studyTimeStepPercent,
} from "./queue";

// The day's new cards from the user's own study time and pace, by the rules of study.md, as
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
 * The time the user studies on a study day, in whole milliseconds, from [days], the study days
 * of the window, oldest first. Each day's estimate is the mean of the days up to it, each
 * weighted 0.5^(age / `studyTimeHalfLife`) with the age in study days, held within
 * `studyTimeStepPercent` of the day before's; the last is returned.
 */
export function studyTime(days: readonly StudyDayTotal[]): number {
  let time: number | null = null;
  for (let upto = 0; upto < days.length; upto++) {
    let sum = 0;
    let weights = 0;
    for (let index = 0; index <= upto; index++) {
      const weight = 0.5 ** ((upto - index) / studyTimeHalfLife);
      const day = days[index];
      if (!day) continue;
      sum += weight * (day.reviewMs + day.firstMs);
      weights += weight;
    }
    const next = sum / weights;
    const step = studyTimeStepPercent / 100;
    time = time === null ? next : Math.min(Math.max(next, time * (1 - step)), time * (1 + step));
  }
  return Math.round(time ?? 0);
}

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
 * How many new cards a study day takes, across every deck, from [days], the study days of the
 * window before it, oldest first; [due], the reviews due in it when it started; and [load], the
 * collection's `dailyLoad` then. While [days] holds fewer than `coldStartStudyDays`,
 * `coldStartNewCards`. Otherwise the `studyTime` left after the reviews set aside, at the review
 * pace in whole milliseconds, divided by the first-answer pace, rounded down, never below zero.
 * The reviews set aside are [load], with the reviews due beyond it spread over
 * `reviewSpreadDays`.
 */
export function dailyNewCards(
  days: readonly StudyDayTotal[],
  { due, load }: { due: number; load: number },
): number {
  if (days.length < coldStartStudyDays) return coldStartNewCards;
  const pace = paceOf(days);
  const setAside = load + Math.max(0, due - load) / reviewSpreadDays;
  const left = studyTime(days) - Math.round(setAside * pace.reviewMs);
  return Math.max(0, Math.trunc(left / pace.firstMs));
}

/** The whole minutes [reviews] reviews and [fresh] new cards take at [pace], rounded up. */
export function sessionMinutes(reviews: number, fresh: number, pace: Pace): number {
  return Math.ceil((reviews * pace.reviewMs + fresh * pace.firstMs) / 60_000);
}
