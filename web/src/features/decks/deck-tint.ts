import type { DeckId } from "./library";

/** The four tints a deck's initial tile is drawn on, as theme colour utilities, in order. */
export const deckTints = ["bg-tint-blue", "bg-tint-amber", "bg-tint-green", "bg-tint-red"] as const;

/**
 * Which tint a deck's tile takes: the sum of its id's UTF-16 code units, modulo the tints. The
 * app computes the same (`deckTintIndex` in app/lib/deck/src/deck_list_screen.dart).
 */
export function deckTintIndex(deck: DeckId): number {
  let sum = 0;
  for (let i = 0; i < deck.length; i++) sum += deck.charCodeAt(i);
  return sum % deckTints.length;
}

/** The tint utility of a deck's tile; the index is always in range, so the fallback never runs. */
export function deckTint(deck: DeckId): (typeof deckTints)[number] {
  return deckTints[deckTintIndex(deck)] ?? deckTints[0];
}
