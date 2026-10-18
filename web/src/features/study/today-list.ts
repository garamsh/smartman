import type { CardId } from "@/features/decks";

import type { Answer } from "./answer-write";
import { type Today, todaysList } from "./engine-wasm/smartman_engine_wasm.js";
import type { CardStates, SelectedQueue } from "./queue";

export type { Today };

/** An answer as today's list reads it. Times are milliseconds since the epoch. */
export type DayAnswer = { cardId: CardId; answer: Answer; reviewedAt: number };

/**
 * Where each of [cards] stands in [day]'s list, through the engine's `today` (engine.md): from
 * the due time of its stored state in [states], none for a card never reviewed, and its
 * [answers] of the day, in any order. A card is "left" when its latest answer in the day is
 * "모른다", or when it has none and falls due before the day ends; "done" when its latest answer
 * in the day is "안다"; otherwise "absent". The engine counts whole seconds, so times are
 * truncated. The engine module must be loaded: `loadEngine` in the browser, `loadServerEngine`
 * on the server.
 */
export function todayOf(
  cards: Iterable<CardId>,
  states: CardStates,
  answers: readonly DayAnswer[],
  day: { start: number; end: number },
): Map<CardId, Today> {
  const ids = [...cards];
  const reviews = new Map<CardId, { answer: Answer; at: bigint }[]>();
  for (const answer of answers) {
    const list = reviews.get(answer.cardId) ?? [];
    list.push({ answer: answer.answer, at: toSeconds(answer.reviewedAt) });
    reviews.set(answer.cardId, list);
  }
  const places = todaysList(
    ids.map((id) => {
      const state = states[id];
      return { due: state ? toSeconds(state.due) : null, reviews: reviews.get(id) ?? [] };
    }),
    toSeconds(day.start),
    toSeconds(day.end),
  );
  return new Map(ids.map((id, index) => [id, places[index] ?? "absent"]));
}

/**
 * [selected] with the cards of [cards] that today's list keeps [places] "left" but the queue
 * rules did not select: those answered "모른다" last today, which their state no longer makes
 * due. They join after the selected cards; the session orders them all together.
 */
export function withTodaysLeft<C extends { id: CardId }>(
  selected: SelectedQueue<C>,
  cards: readonly C[],
  places: ReadonlyMap<CardId, Today>,
): SelectedQueue<C> {
  const chosen = new Set(selected.cards.map((card) => card.id));
  return {
    backlog: selected.backlog,
    cards: [
      ...selected.cards,
      ...cards.filter((card) => places.get(card.id) === "left" && !chosen.has(card.id)),
    ],
  };
}

function toSeconds(milliseconds: number): bigint {
  return BigInt(Math.trunc(milliseconds / 1000));
}
