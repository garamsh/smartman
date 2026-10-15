import type { Content } from "@/lib/card-content";

/** A deck's id, as the phone created it. */
export type DeckId = string & { readonly brand: "DeckId" };

/** A card's id, as the phone created it. */
export type CardId = string & { readonly brand: "CardId" };

/** A deck that is not deleted. */
export type Deck = { id: DeckId; name: string };

/** A card that is not deleted, in a deck that is not. Times are milliseconds since the epoch. */
export type Card = {
  id: CardId;
  deckId: DeckId;
  front: Content[];
  back: Content[];
  createdAt: number;
};

/** The signed-in user's decks, by name, and their cards, oldest first. */
export type Library = { decks: Deck[]; cards: Card[] };
