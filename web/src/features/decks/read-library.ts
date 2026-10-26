import "server-only";

import { requestTimeoutMs, type ServerFailure } from "@/supabase/failure";
import { selectAll } from "@/supabase/select-all";
import { field, parseTime } from "@/supabase/row";
import { createClient } from "@/supabase/server";
import { readUserId } from "@/supabase/session";

import { parseContent } from "./card-content";
import type { Card, CardEntry, CardId, Deck, DeckId, Library } from "./library";

/** Why the library could not be read: a server failure, or a row this version cannot read. */
export type LibraryFailure = ServerFailure | "unreadable";

/**
 * The decks [decks] names, or every deck, of the signed-in user, with their cards and both
 * sides of each; see [readDeckList] for what both reads leave out.
 */
export function readLibrary(
  decks?: readonly DeckId[],
): Promise<{ library: Library } | { failure: LibraryFailure }> {
  return read("id, deck_id, front, back, created_at", parseCard, decks);
}

/**
 * Every deck of the signed-in user, with its cards but not their content: what the deck list
 * shows and counts. Both reads run under row-level security and leave out every tombstoned row
 * and every card of a tombstoned deck. Row-level security also lets a user read other users'
 * public decks, so they filter on the user's own.
 */
export function readDeckList(): Promise<
  { library: Library<CardEntry> } | { failure: LibraryFailure }
> {
  return read("id, deck_id, created_at", parseCardEntry);
}

async function read<C extends CardEntry>(
  cardColumns: string,
  parse: (row: unknown) => C | null,
  decks?: readonly DeckId[],
): Promise<{ library: Library<C> } | { failure: LibraryFailure }> {
  const supabase = await createClient();
  const session = await readUserId(supabase);
  if ("failure" in session) return session;
  const { userId } = session;
  const [deckRows, cardRows] = await Promise.all([
    selectAll((from, to, counted) => {
      const query = supabase
        .from("decks")
        .select("id, name, visibility, icon, color", counted ? { count: "exact" } : {})
        .eq("user_id", userId)
        .is("deleted_at", null);
      return (decks ? query.in("id", decks) : query)
        .order("id")
        .range(from, to)
        .abortSignal(AbortSignal.timeout(requestTimeoutMs));
    }),
    selectAll((from, to, counted) => {
      const query = supabase
        .from("cards")
        .select(cardColumns, counted ? { count: "exact" } : {})
        .eq("user_id", userId)
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
  const cards: C[] = [];
  for (const row of cardRows.rows) {
    const card = parse(row);
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
  const visibility = field(row, "visibility");
  if (typeof id !== "string" || typeof name !== "string") return null;
  if (visibility !== "private" && visibility !== "public") return null;
  // A key the tile does not know draws the default, so neither key makes a row unreadable.
  const icon = field(row, "icon");
  const color = field(row, "color");
  return {
    id: id as DeckId,
    name,
    public: visibility === "public",
    ...(typeof icon === "string" && { icon }),
    ...(typeof color === "string" && { color }),
  };
}

function parseCardEntry(row: unknown): CardEntry | null {
  const id = field(row, "id");
  const deckId = field(row, "deck_id");
  const createdAt = parseTime(field(row, "created_at"));
  if (typeof id !== "string" || typeof deckId !== "string" || createdAt === null) return null;
  return { id: id as CardId, deckId: deckId as DeckId, createdAt };
}

function parseCard(row: unknown): Card | null {
  const entry = parseCardEntry(row);
  const front = parseContent(field(row, "front"));
  const back = parseContent(field(row, "back"));
  if (!entry || !front || !back) return null;
  return { ...entry, front, back };
}
