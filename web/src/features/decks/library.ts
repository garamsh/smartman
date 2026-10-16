import type { Content } from "./card-content";

/** A deck's id, as the phone created it. */
export type DeckId = string & { readonly brand: "DeckId" };

/** A card's id, as the phone created it. */
export type CardId = string & { readonly brand: "CardId" };

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
