import type { Content } from "./card-content";

/** A deck's id, as the phone created it. */
export type DeckId = string & { readonly brand: "DeckId" };

/** A card's id, as the phone created it. */
export type CardId = string & { readonly brand: "CardId" };

/** A uuid in the canonical lowercase form the server stores and returns ids in. */
const uuid = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/;

/** [value] as a deck's id, or null when it is not one: an address or a request names no deck. */
export function parseDeckId(value: unknown): DeckId | null {
  return typeof value === "string" && uuid.test(value) ? (value as DeckId) : null;
}

/** [value] as a card's id, or null when it is not one. */
export function parseCardId(value: unknown): CardId | null {
  return typeof value === "string" && uuid.test(value) ? (value as CardId) : null;
}

/** A deck that is not deleted, and whether its owner published it. */
export type Deck = { id: DeckId; name: string; public: boolean };

/**
 * A card that is not deleted, in a deck that is not, without its content: what the deck list
 * counts. Times are milliseconds since the epoch.
 */
export type CardEntry = { id: CardId; deckId: DeckId; createdAt: number };

/** A card with its two sides. */
export type Card = CardEntry & { front: Content[]; back: Content[] };

/** The signed-in user's decks, by name, and their cards, oldest first. */
export type Library<C extends CardEntry = Card> = { decks: Deck[]; cards: C[] };
