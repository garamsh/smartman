import "server-only";

import { requestTimeoutMs, type ServerFailure } from "@/lib/supabase/failure";
import { selectAll } from "@/lib/supabase/select-all";
import { field, parseTime } from "@/lib/supabase/row";
import { createClient } from "@/lib/supabase/server";

import { parseContent } from "@/lib/card-content";
import type { Card, CardId, Deck, DeckId, Library } from "./library";

/** Why the library could not be read: a server failure, or a row this version cannot read. */
export type LibraryFailure = ServerFailure | "unreadable";

/**
 * The signed-in user's decks and cards, read from the server under row-level security,
 * leaving out every tombstoned row and every card of a tombstoned deck. With [decks], only
 * the cards of those decks are read.
 */
export async function readLibrary(
  decks?: readonly DeckId[],
): Promise<{ library: Library } | { failure: LibraryFailure }> {
  const supabase = await createClient();
  const [deckRows, cardRows] = await Promise.all([
    selectAll((from, to) =>
      supabase
        .from("decks")
        .select("id, name")
        .is("deleted_at", null)
        .order("id")
        .range(from, to)
        .abortSignal(AbortSignal.timeout(requestTimeoutMs)),
    ),
    selectAll((from, to) => {
      const query = supabase
        .from("cards")
        .select("id, deck_id, front, back, created_at")
        .is("deleted_at", null);
      return (decks ? query.in("deck_id", decks) : query)
        .order("id")
        .range(from, to)
        .abortSignal(AbortSignal.timeout(requestTimeoutMs));
    }),
  ]);
  if ("failure" in deckRows) return deckRows;
  if ("failure" in cardRows) return cardRows;

  const liveDecks: Deck[] = [];
  for (const row of deckRows.rows) {
    const deck = parseDeck(row);
    if (!deck) return { failure: "unreadable" };
    liveDecks.push(deck);
  }
  const live = new Set(liveDecks.map((deck) => deck.id));
  const cards: Card[] = [];
  for (const row of cardRows.rows) {
    const card = parseCard(row);
    if (!card) return { failure: "unreadable" };
    if (live.has(card.deckId)) cards.push(card);
  }
  // The phone's orders: decks by name, cards by creation; ties by id, so every read agrees.
  liveDecks.sort((a, b) => compare(a.name, b.name) || compare(a.id, b.id));
  cards.sort((a, b) => a.createdAt - b.createdAt || compare(a.id, b.id));
  return { library: { decks: liveDecks, cards } };
}

function compare(a: string, b: string): number {
  return a < b ? -1 : a > b ? 1 : 0;
}

function parseDeck(row: unknown): Deck | null {
  const id = field(row, "id");
  const name = field(row, "name");
  if (typeof id !== "string" || typeof name !== "string") return null;
  return { id: id as DeckId, name };
}

function parseCard(row: unknown): Card | null {
  const id = field(row, "id");
  const deckId = field(row, "deck_id");
  const createdAt = parseTime(field(row, "created_at"));
  const front = parseContent(field(row, "front"));
  const back = parseContent(field(row, "back"));
  if (typeof id !== "string" || typeof deckId !== "string") return null;
  if (createdAt === null || !front || !back) return null;
  return { id: id as CardId, deckId: deckId as DeckId, front, back, createdAt };
}
