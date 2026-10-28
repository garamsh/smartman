import type { CardId } from "@/features/decks";

import {
  answerCapMs,
  type CardState,
  type CardStates,
  type StudyDay,
  studyDayEnd,
  studyDayStart,
} from "./queue";
import type { RecordDay } from "./stats";
import { type DayPlan, leftOf } from "./today-list";

// What the 오늘 page and the deck pages show of a selection beyond its queue, by the definitions
// of study.md, as app/lib/study/src/overview.dart computes them on the phone.

/** The interval, in days, from which a reviewed card counts as mastered (익힘). */
export const masteredIntervalDays = 21;

/** How many study days the 오늘 page's charts cover, today included: the last seven. */
export const chartDays = 7;

const day = 86_400_000;

/** How far a card has come: 익힘, 학습 중 or 새 카드. */
export type CardProgress = "mastered" | "learning" | "fresh";

/**
 * The progress of a card whose stored state is [state], undefined when it was never reviewed.
 * The current interval is the time from its last review to its due time.
 */
export function progressOf(state: CardState | undefined): CardProgress {
  if (!state) return "fresh";
  return state.due - state.lastReview >= masteredIntervalDays * day ? "mastered" : "learning";
}

/** How many of a selection's cards are mastered, learning and new. */
export type DeckProgress = { mastered: number; learning: number; fresh: number };

/** The progress of every one of [cards], from the stored [states] of those reviewed. */
export function deckProgress(cards: Iterable<{ id: CardId }>, states: CardStates): DeckProgress {
  const progress = { mastered: 0, learning: 0, fresh: 0 };
  for (const card of cards) progress[progressOf(states[card.id])] += 1;
  return progress;
}

/**
 * The first study day after [today], within `chartDays` of it, on which one of the stored
 * [states] falls due in [timeZone]: how many days after [today] it is, and how many cards fall due
 * in it; null when none does.
 */
export function nextReviewOf(
  states: Iterable<CardState>,
  today: StudyDay,
  timeZone: string,
): { after: number; cards: number } | null {
  const ends = [today.end];
  while (ends.length < chartDays) {
    ends.push(studyDayEnd(ends[ends.length - 1] ?? today.end, timeZone));
  }
  const counts = Array.from({ length: chartDays }, () => 0);
  for (const state of states) {
    // A card due before the day ends, today's or overdue, is on no later day.
    const index = ends.findIndex((end) => state.due < end);
    if (index > 0) counts[index] = (counts[index] ?? 0) + 1;
  }
  const after = counts.findIndex((count, index) => index > 0 && count > 0);
  return after > 0 ? { after, cards: counts[after] ?? 0 } : null;
}

/**
 * The overdue reviews left at the start of each of the `chartDays` study days from today, when
 * [backlog] are overdue today and the user clears [perDay] of them a day: the catch-up a backlog
 * card projects.
 */
export function catchUp(backlog: number, perDay: number): number[] {
  return Array.from({ length: chartDays }, (_, day) => Math.max(0, backlog - day * perDay));
}

/**
 * One of the last `chartDays` study days: when it starts, the cards answered in it, each once, and
 * the time its answers took, each up to `answerCapMs`, in milliseconds.
 */
export type WeekDay = { start: number; cards: number; ms: number };

/**
 * The last `chartDays` study days, oldest first, ending with the one starting at [todayStart] in
 * [timeZone], as the phone's `lastWeek` counts them: each day's cards from the server's study days
 * [days] (`study_record_days`), each earlier day's time from [times] (`study_days_before`, capped
 * there), and today's from its [today] answers. A day without an answer has no cards and no time.
 */
export function lastWeek({
  days,
  times,
  today,
  todayStart,
  timeZone,
}: {
  days: readonly RecordDay[];
  times: readonly { dayStart: number; ms: number }[];
  today: readonly { durationMs: number }[];
  todayStart: number;
  timeZone: string;
}): WeekDay[] {
  const starts = [todayStart];
  while (starts.length < chartDays) {
    // An hour before a day's start lies in the day before, whatever the offset does.
    starts.unshift(studyDayStart((starts[0] ?? todayStart) - 3_600_000, timeZone));
  }
  const cards = new Map(days.map((day) => [day.dayStart, day.cards]));
  const ms = new Map(times.map((time) => [time.dayStart, time.ms]));
  ms.set(
    todayStart,
    today.reduce((sum, { durationMs }) => sum + Math.min(durationMs, answerCapMs), 0),
  );
  return starts.map((start) => ({
    start,
    cards: cards.get(start) ?? 0,
    ms: ms.get(start) ?? 0,
  }));
}

/** The daily goal: [done] of the [goal] cards the study day held. */
export type DailyGoal = { done: number; goal: number };

/**
 * The daily goal from today's [plan], as today's list places the cards: done are those answered
 * "안다" last today, and the goal adds those left, the selection and the cards still on "모른다". A
 * card answered "모른다" is left until it is answered "안다".
 */
export function dailyGoal(plan: DayPlan<unknown>): DailyGoal {
  return { done: plan.done.size, goal: plan.done.size + leftOf(plan) };
}
