import { cache } from "react";

import { type DeckId, readLibrary } from "@/features/decks";

/** The deck [id] names with its cards, read once per request for both the page and its title. */
export const readDeck = cache((id: DeckId) => readLibrary([id]));
