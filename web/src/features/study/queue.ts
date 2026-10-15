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

/**
 * The cards are in backlog when more than this many days of reviews are due: the due count
 * against this multiple of `dailyLoad`.
 */
export const backlogDays = 3;

/** How many consecutive cards of a backlog's order are shuffled together. */
export const backlogBucketSize = 10;

/** A day, in milliseconds. */
const day = 86_400_000;

/** A reviewed card's stored scheduling state. Times are milliseconds since the epoch. */
export type CardState = {
  stability: number;
  difficulty: number;
  lastReview: number;
  due: number;
};

/** The stored state of each reviewed card; a card never reviewed has none. */
export type CardStates = Partial<Record<CardId, CardState>>;

/**
 * What a session over some cards would study now. In a backlog, `fresh` is 0: new cards pause
 * until the reviews are done.
 */
export type TodayCount = { review: number; fresh: number; backlog: boolean };

/**
 * The cards a session studies. In a backlog: every due card, earliest due first, and no new
 * card. Otherwise: every due card, then up to [newCardLimit] new ones, oldest first.
 */
export type SelectedQueue<C> = { cards: C[]; backlog: boolean };

type Queueable = { id: CardId; createdAt: number };

/**
 * The reviews a day [states] ask for at their current intervals: the sum, over every reviewed
 * card, of one over its interval in days, at least one.
 */
export function dailyLoad(states: Iterable<CardState>): number {
  let load = 0;
  for (const state of states) load += 1 / Math.max((state.due - state.lastReview) / day, 1);
  return load;
}

/**
 * The cards a session starting at [now] studies, from [cards] and their stored [states]. They
 * are in backlog when more than [backlogDays] of `dailyLoad` are due at or before [now]: the
 * session then takes every due card, earliest due first, ties in the order given, and no new
 * card. Otherwise it takes every due card, then up to [newCardLimit] cards with no state,
 * oldest first by creation time, ties in the order given.
 */
export function selectQueue<C extends Queueable>(
  cards: readonly C[],
  states: CardStates,
  now: number,
): SelectedQueue<C> {
  const due: { card: C; due: number }[] = [];
  const fresh: C[] = [];
  const reviewed: CardState[] = [];
  for (const card of cards) {
    const state = states[card.id];
    if (!state) {
      fresh.push(card);
      continue;
    }
    reviewed.push(state);
    if (state.due <= now) due.push({ card, due: state.due });
  }
  // Array.prototype.sort is stable, so equal times keep the order given.
  if (due.length > backlogDays * dailyLoad(reviewed)) {
    due.sort((a, b) => a.due - b.due);
    return { cards: due.map((entry) => entry.card), backlog: true };
  }
  fresh.sort((a, b) => a.createdAt - b.createdAt);
  return {
    cards: [...due.map((entry) => entry.card), ...fresh.slice(0, newCardLimit)],
    backlog: false,
  };
}

/** How many due and new cards a session over [cards] starting at [now] would study. */
export function countToday(
  cards: readonly Queueable[],
  states: CardStates,
  now: number,
): TodayCount {
  const queue = selectQueue(cards, states, now);
  const review = queue.cards.filter((card) => states[card.id]).length;
  return { review, fresh: queue.cards.length - review, backlog: queue.backlog };
}

/**
 * [queue]'s cards in an order drawn from [random]. In a backlog, each run of
 * [backlogBucketSize] consecutive cards is shuffled in its place, so earlier due cards still
 * come first. Otherwise every order is equally likely: the due cards shuffled, with each new
 * card at a random place among them. Each draw picks the next card from those of its run not
 * yet placed, the first of them on a draw of 0.
 */
export function orderQueue<C>(queue: SelectedQueue<C>, random: Random): C[] {
  const run = queue.backlog ? backlogBucketSize : Math.max(queue.cards.length, 1);
  const ordered: C[] = [];
  for (let start = 0; start < queue.cards.length; start += run) {
    const remaining = queue.cards.slice(start, start + run);
    while (remaining.length > 0) {
      ordered.push(...remaining.splice(random.nextInt(remaining.length), 1));
    }
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
