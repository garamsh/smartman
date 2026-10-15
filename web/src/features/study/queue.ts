import type { CardId } from "@/features/decks";

import type { Random } from "./random";

// The queue rules of study.md, in one place: which cards a session studies, in what order, and
// when a "Don't know" comes back. The counts the deck screens show come from the same rules.

/** How many never-reviewed cards one session takes, across all its decks. */
export const newCardLimit = 20;

/** The fewest other cards shown before a "Don't know" card comes back. */
export const reshowGapMin = 3;

/** The most other cards shown before a "Don't know" card comes back. */
export const reshowGapMax = 5;

/** A reviewed card's stored scheduling state. Times are milliseconds since the epoch. */
export type CardState = {
  stability: number;
  difficulty: number;
  lastReview: number;
  due: number;
};

/** The stored state of each reviewed card; a card never reviewed has none. */
export type CardStates = Partial<Record<CardId, CardState>>;

/** What a session over some cards would study now. */
export type TodayCount = { review: number; fresh: number };

type Queueable = { id: CardId; createdAt: number };

/**
 * The cards a session starting at [now] studies, from [cards] and their stored [states]:
 * every card due at or before [now], then up to [newCardLimit] cards with no state, oldest
 * first by creation time, ties in the order given.
 */
export function selectQueue<C extends Queueable>(
  cards: readonly C[],
  states: CardStates,
  now: number,
): C[] {
  const due: C[] = [];
  const fresh: C[] = [];
  for (const card of cards) {
    const state = states[card.id];
    if (!state) fresh.push(card);
    else if (state.due <= now) due.push(card);
  }
  // Array.prototype.sort is stable, so equal creation times keep the order given.
  fresh.sort((a, b) => a.createdAt - b.createdAt);
  return [...due, ...fresh.slice(0, newCardLimit)];
}

/** How many due and new cards a session over [cards] starting at [now] would study. */
export function countToday(
  cards: readonly Queueable[],
  states: CardStates,
  now: number,
): TodayCount {
  const queue = selectQueue(cards, states, now);
  const review = queue.filter((card) => states[card.id]).length;
  return { review, fresh: queue.length - review };
}

/**
 * [queue] in an order drawn from [random], every order equally likely: the due cards shuffled,
 * with each new card at a random place among them. Each draw picks the next card from those
 * not yet placed, the first of them on a draw of 0.
 */
export function orderQueue<C>(queue: readonly C[], random: Random): C[] {
  const remaining = [...queue];
  const ordered: C[] = [];
  while (remaining.length > 0) {
    ordered.push(...remaining.splice(random.nextInt(remaining.length), 1));
  }
  return ordered;
}

/**
 * Puts [card] back into [queue], the cards still to show with the next one first, so that a
 * gap drawn from [random] between [reshowGapMin] and [reshowGapMax] other cards come before
 * it, or as many as remain.
 */
export function reinsert<C>(queue: C[], card: C, random: Random): void {
  const gap = reshowGapMin + random.nextInt(reshowGapMax - reshowGapMin + 1);
  queue.splice(Math.min(gap, queue.length), 0, card);
}
