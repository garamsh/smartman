import type { Deck, DeckId } from "./library";

/**
 * The deck palette's colours by the key a deck stores, in the app's order (`DeckColor` in
 * app/lib/deck/src/model.dart), each with its theme colour utility.
 */
const deckFills = {
  blue: "bg-deck-blue",
  sky: "bg-deck-sky",
  violet: "bg-deck-violet",
  amber: "bg-deck-amber",
  slate: "bg-deck-slate",
  sand: "bg-deck-sand",
} as const;

/** A colour of the deck palette, by the key a deck stores. */
export type DeckColor = keyof typeof deckFills;

/** The palette's colours, in the app's order. */
export const deckColors = Object.keys(deckFills) as DeckColor[];

/**
 * Which colour a deck takes while it holds none this version knows: the sum of its id's UTF-16
 * code units, modulo the palette's six. The app computes the same (`deckTintIndex(id, 6)` in
 * app/lib/deck/src/deck_row.dart).
 */
export function deckTintIndex(deck: DeckId): number {
  let sum = 0;
  for (let i = 0; i < deck.length; i++) sum += deck.charCodeAt(i);
  return sum % deckColors.length;
}

/** The colour [deck]'s tile takes: the one it stores, or, for none or a key this version does not know, the one its id selects. */
export function deckColor(deck: Deck): DeckColor {
  const stored = deck.color;
  if (stored !== undefined && Object.hasOwn(deckFills, stored)) return stored as DeckColor;
  // The index is always in range, so the fallback never runs.
  return deckColors[deckTintIndex(deck.id)] ?? "blue";
}

/** The theme colour utility of [color]. */
export function deckFill(color: DeckColor): string {
  return deckFills[color];
}
