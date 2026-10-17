import type { CardId } from "@/features/decks";

import { progressOf } from "./overview";
import { type CardState, studyDayEnd, studyDayStart } from "./queue";

// The 기록 page's metrics, ADR 0037's definitions, as app/lib/study/src/stats.dart computes them
// on the phone. The server's study_record_days groups the answers by study day as
// [recordDays] does (ADR 0047).

/** The probability of recall the engine schedules each review for: `DESIRED_RETENTION`. */
export const targetRetention = 0.9;

/** One study day with an answer: its start, the distinct cards answered, its scheduled reviews and those known. */
export type RecordDay = { dayStart: number; cards: number; reviews: number; known: number };

/** A stored answer, as [recordDays] reads it. */
export type RecordAnswer = { cardId: CardId; know: boolean; reviewedAt: number };

/**
 * Each study day in [timeZone] holding one of [answers], oldest first. A review is scheduled when
 * it is a card's first answer of its study day and the card has an answer on an earlier one: a
 * card's first answer ever, and a re-show after "모른다" on the same day, are left out.
 */
export function recordDays(answers: Iterable<RecordAnswer>, timeZone: string): RecordDay[] {
  const ordered = [...answers].sort((a, b) => a.reviewedAt - b.reviewedAt);
  const lastDay = new Map<CardId, number>();
  const days = new Map<number, { cards: Set<CardId>; reviews: number; known: number }>();
  for (const answer of ordered) {
    const dayStart = studyDayStart(answer.reviewedAt, timeZone);
    const day = days.get(dayStart) ?? { cards: new Set<CardId>(), reviews: 0, known: 0 };
    days.set(dayStart, day);
    day.cards.add(answer.cardId);
    const previous = lastDay.get(answer.cardId);
    lastDay.set(answer.cardId, dayStart);
    if (previous === undefined || previous >= dayStart) continue;
    day.reviews += 1;
    if (answer.know) day.known += 1;
  }
  return [...days.entries()]
    .sort(([a], [b]) => a - b)
    .map(([dayStart, day]) => ({
      dayStart,
      cards: day.cards.size,
      reviews: day.reviews,
      known: day.known,
    }));
}

/** How many scheduled reviews were answered "안다", out of how many, at least one. */
export type Retention = { reviews: number; known: number };

/** The share of [retention] answered "안다", from 0 to 1. */
export function share(retention: Retention): number {
  return retention.known / retention.reviews;
}

/** The retention over every scheduled review of [days]; null when they hold none. */
export function retentionOver(days: Iterable<RecordDay>): Retention | null {
  let reviews = 0;
  let known = 0;
  for (const day of days) {
    reviews += day.reviews;
    known += day.known;
  }
  return reviews === 0 ? null : { reviews, known };
}

/** A span of study days the retention is shown over: the last 7 or 30, today's included, or every one. */
export type StatsPeriod = "week" | "month" | "all";

const periodDays: Record<StatsPeriod, number | null> = { week: 7, month: 30, all: null };

/** When [period]'s first study day starts, as of [now] in [timeZone]; null for every study day. */
export function periodStart(period: StatsPeriod, now: number, timeZone: string): number | null {
  const days = periodDays[period];
  if (days === null) return null;
  let start = studyDayStart(now, timeZone);
  for (let day = 1; day < days; day += 1) start = dayBefore(start, timeZone);
  return start;
}

/** The days of [days] within [period] as of [now], in [timeZone], that hold a scheduled review. */
export function retentionIn(
  days: readonly RecordDay[],
  period: StatsPeriod,
  now: number,
  timeZone: string,
): RecordDay[] {
  const start = periodStart(period, now, timeZone) ?? -Infinity;
  return days.filter((day) => day.reviews > 0 && day.dayStart >= start);
}

/** The probability of recall from which a card's recall is strong (단단함). */
export const strongRecall = 0.95;

/** The probability of recall below which a card is fading (곧 잊음). */
export const fadingRecall = 0.8;

/** How many cards fall in each band, and their mean probability of recall, null without a card. */
export type RecallBands = { strong: number; fair: number; fading: number; mean: number | null };

/** The bands of the cards whose probabilities of recall are [recalls], each bound in the upper band. */
export function recallBands(recalls: Iterable<number>): RecallBands {
  const bands = { strong: 0, fair: 0, fading: 0 };
  let sum = 0;
  for (const recall of recalls) {
    sum += recall;
    if (recall >= strongRecall) bands.strong += 1;
    else if (recall >= fadingRecall) bands.fair += 1;
    else bands.fading += 1;
  }
  const total = bands.strong + bands.fair + bands.fading;
  return { ...bands, mean: total === 0 ? null : sum / total };
}

/** How many weeks [masteredByWeek] covers, this one included. */
export const masteredWeeks = 8;

/**
 * The cards mastered at the end of each of the last [masteredWeeks] weeks of seven study days in
 * [timeZone], oldest first, the last ending with today's study day. [histories] holds each card's
 * states after each of its reviews, in order; at a week's end a card has the state of its latest
 * review before it, and is mastered by `progressOf`, from a 21-day interval.
 */
export function masteredByWeek(
  histories: Iterable<readonly CardState[]>,
  now: number,
  timeZone: string,
): number[] {
  // Each earlier week ends where the study day after its last one starts.
  const starts = [studyDayStart(now, timeZone)];
  while (starts.length < 7 * (masteredWeeks - 1)) {
    starts.push(dayBefore(starts[starts.length - 1] ?? now, timeZone));
  }
  const ends = [studyDayEnd(starts[0] ?? now, timeZone)];
  for (let week = 1; week < masteredWeeks; week += 1) ends.push(starts[7 * week - 1] ?? now);
  const cards = [...histories];
  return ends.reverse().map(
    (end) =>
      cards.filter((states) => {
        let latest: CardState | undefined;
        for (const state of states) {
          if (state.lastReview >= end) break;
          latest = state;
        }
        return progressOf(latest) === "mastered";
      }).length,
  );
}

/** How many more cards are mastered this week than four weeks before; null unless more are. */
export function masteredGain(weeks: readonly number[]): number | null {
  const gain = (weeks[weeks.length - 1] ?? 0) - (weeks[weeks.length - 5] ?? 0);
  return gain > 0 ? gain : null;
}

/** How many study days the heatmap covers: twelve weeks. */
export const heatmapDays = 84;

/** The cards answered on a study day, and the calendar date it starts on, at midnight UTC. */
export type StudyDayCount = { date: number; cards: number };

/**
 * The distinct cards answered on each of the last [heatmapDays] study days, oldest first, the
 * last being today's, in [timeZone], from [days].
 */
export function studyDayCounts(
  days: readonly RecordDay[],
  now: number,
  timeZone: string,
): StudyDayCount[] {
  const cards = new Map(days.map((day) => [day.dayStart, day.cards]));
  const starts = [studyDayStart(now, timeZone)];
  while (starts.length < heatmapDays) {
    starts.push(dayBefore(starts[starts.length - 1] ?? now, timeZone));
  }
  return starts.reverse().map((start) => ({
    date: calendarDate(start, timeZone),
    cards: cards.get(start) ?? 0,
  }));
}

/** How many levels a heatmap cell is drawn at, a day without a card included. */
export const heatLevels = 4;

/**
 * The level a study day with [cards] is drawn at when the busiest day of the heatmap holds
 * [most]: 0 without a card, then 1 to 3 by which third of 1 to [most] it falls in.
 */
export function heatLevel(cards: number, most: number): number {
  if (cards <= 0) return 0;
  return Math.min(heatLevels - 1, Math.max(1, Math.ceil((3 * cards) / most)));
}

/** The most study days in a row in [timeZone] that hold one of [answers]. */
export function bestStreak(answers: Iterable<number>, timeZone: string): number {
  const days = [...new Set([...answers].map((at) => studyDayStart(at, timeZone)))].sort(
    (a, b) => a - b,
  );
  let best = 0;
  let run = 0;
  let previous: number | null = null;
  for (const start of days) {
    run = previous !== null && studyDayEnd(previous, timeZone) === start ? run + 1 : 1;
    best = Math.max(best, run);
    previous = start;
  }
  return best;
}

/** The start of the study day before the one starting at [start] in [timeZone]. */
function dayBefore(start: number, timeZone: string): number {
  return studyDayStart(start - 1000, timeZone);
}

/** The calendar date, at midnight UTC, that the study day starting at [start] starts on in [timeZone]. */
export function calendarDate(start: number, timeZone: string): number {
  const parts = new Intl.DateTimeFormat("en-CA", {
    timeZone,
    year: "numeric",
    month: "2-digit",
    day: "2-digit",
  }).formatToParts(start);
  const part = (type: Intl.DateTimeFormatPartTypes) =>
    Number(parts.find((entry) => entry.type === type)?.value);
  return Date.UTC(part("year"), part("month") - 1, part("day"));
}
