import type { CardId } from "@/features/decks";

import { type CardState, type CardStates, type StudyDay, studyDayEnd } from "./queue";

// What the 오늘 page and the deck pages show of a selection beyond its queue, by the definitions
// of study.md, as app/lib/study/src/overview.dart computes them on the phone.

/** The interval, in days, from which a reviewed card counts as mastered (익힘). */
export const masteredIntervalDays = 21;

/** How many study days the forecast covers, today included. */
export const forecastDays = 7;

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
 * The cards due on each of the `forecastDays` study days from [today]: today's [load], then, for
 * each later day, the stored [states] that fall due within it, in [timeZone].
 */
export function forecast(
  states: Iterable<CardState>,
  today: StudyDay,
  load: number,
  timeZone: string,
): number[] {
  const ends = [today.end];
  while (ends.length < forecastDays)
    ends.push(studyDayEnd(ends[ends.length - 1] ?? today.end, timeZone));
  const counts = Array.from({ length: forecastDays }, (_, index) => (index === 0 ? load : 0));
  for (const state of states) {
    const index = ends.findIndex((end) => state.due < end);
    // A card due within today is in the load already; one past the last day is in none.
    if (index > 0) counts[index] = (counts[index] ?? 0) + 1;
  }
  return counts;
}

/** The daily goal: [done] of the [goal] cards the study day held. */
export type DailyGoal = { done: number; goal: number };

/**
 * The goal of the study [today] from the recorded [answers] and the cards [left] to study in it:
 * every card answered within the day or left, each once, as the load stood when the day started;
 * done are those no longer left. A card answered "모른다" and due again today is left, so not
 * yet done. Practice records nothing, so it counts toward neither.
 */
export function dailyGoal(
  answers: Iterable<{ cardId: CardId; reviewedAt: number }>,
  left: Iterable<CardId>,
  today: StudyDay,
): DailyGoal {
  const remaining = new Set(left);
  const cards = new Set(remaining);
  for (const answer of answers) {
    if (answer.reviewedAt >= today.start && answer.reviewedAt < today.end) cards.add(answer.cardId);
  }
  return { done: cards.size - remaining.size, goal: cards.size };
}

/**
 * Where the user stands today, which the today card states in place of the goal's numbers, which
 * its ring shows. It states where the user is and never what to tap.
 */
export type TodayStatus =
  | { kind: "streak"; days: number }
  | { kind: "waiting" }
  | { kind: "almostDone" }
  | { kind: "pastHalf" }
  | { kind: "started" };

/**
 * The first status that holds for [goal] with a [streak] of study days: nothing done yet with a
 * streak of two days or more; nothing done yet; three cards or fewer left; half of the goal or
 * more done; some done.
 */
export function todayStatus(goal: DailyGoal, streak: number): TodayStatus {
  const left = goal.goal - goal.done;
  if (goal.done === 0) return streak >= 2 ? { kind: "streak", days: streak } : { kind: "waiting" };
  if (left <= 3) return { kind: "almostDone" };
  if (goal.done * 2 >= goal.goal) return { kind: "pastHalf" };
  return { kind: "started" };
}

/** The line the today card shows for [status], as the phone words it. */
export function statusLine(status: TodayStatus): string {
  switch (status.kind) {
    case "streak":
      return `${String(status.days)}일째 이어 가는 중이에요`;
    case "waiting":
      return "오늘의 첫 카드를 기다리고 있어요";
    case "almostDone":
      return "거의 다 왔어요";
    case "pastHalf":
      return "절반을 넘었어요";
    case "started":
      return "좋은 출발이에요";
  }
}
