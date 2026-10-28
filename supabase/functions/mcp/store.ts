/**
 * The function's reads and writes, each through PostgREST as the caller: the user's token and the
 * anon key, so row-level security decides every row, never the service-role key (ADR 0126).
 */

import { SupabaseError, type UserId } from "../_shared/auth.ts";

/** The caller's connection to the project's REST API. */
export type Store = {
  readonly url: string;
  readonly anonKey: string;
  readonly token: string;
  readonly userId: UserId;
  readonly fetch: typeof fetch;
};

/** The most rows the project's API returns for one request (`config.toml`, `max_rows`). */
const PAGE = 1000;

async function request(
  store: Store,
  path: string,
  init: { method?: string; body?: unknown; prefer?: string } = {},
): Promise<Response> {
  const headers: Record<string, string> = {
    apikey: store.anonKey,
    Authorization: `Bearer ${store.token}`,
  };
  if (init.body !== undefined) headers["Content-Type"] = "application/json";
  if (init.prefer !== undefined) headers.Prefer = init.prefer;
  const response = await store.fetch(`${store.url}/rest/v1/${path}`, {
    method: init.method ?? "GET",
    headers,
    body: init.body === undefined ? undefined : JSON.stringify(init.body),
  }).catch((cause: unknown) => {
    throw new SupabaseError("the REST API could not be reached", { cause });
  });
  if (!response.ok) {
    await response.body?.cancel();
    throw new SupabaseError(`the REST API answered ${response.status}`);
  }
  return response;
}

async function rows(
  store: Store,
  path: string,
): Promise<Record<string, unknown>[]> {
  const body: unknown = await (await request(store, path)).json();
  if (!Array.isArray(body)) {
    throw new SupabaseError("the REST API answered without rows");
  }
  return body.map((row: unknown) => {
    if (typeof row !== "object" || row === null || Array.isArray(row)) {
      throw new SupabaseError(
        "the REST API answered a row that is not an object",
      );
    }
    return row as Record<string, unknown>;
  });
}

/** Every row [path] selects, a page at a time, in the order it names. */
async function allRows(
  store: Store,
  path: string,
): Promise<Record<string, unknown>[]> {
  const all: Record<string, unknown>[] = [];
  for (let offset = 0;; offset += PAGE) {
    const page = await rows(store, `${path}&limit=${PAGE}&offset=${offset}`);
    all.push(...page);
    if (page.length < PAGE) return all;
  }
}

function text(row: Record<string, unknown>, column: string): string {
  const value = row[column];
  if (typeof value !== "string") {
    throw new SupabaseError(`the REST API answered a row without ${column}`);
  }
  return value;
}

/** A deck of the caller's, as the tools return it. */
export type Deck = { readonly id: string; readonly name: string };

/** The caller's own filter: a public deck of another user is readable too, and never listed. */
function own(store: Store): string {
  return `user_id=eq.${store.userId}&deleted_at=is.null`;
}

/** The caller's live decks, oldest first, with each one's live card count. */
export async function listDecks(
  store: Store,
): Promise<(Deck & { card_count: number })[]> {
  const found = await allRows(
    store,
    `decks?select=id,name,cards(count)&${
      own(store)
    }&cards.deleted_at=is.null&order=created_at.asc,id.asc`,
  );
  return found.map((row) => {
    const counted = Array.isArray(row.cards) ? row.cards[0] : undefined;
    const count =
      typeof counted === "object" && counted !== null && "count" in counted
        ? counted.count
        : undefined;
    if (typeof count !== "number") {
      throw new SupabaseError("the REST API answered no card count");
    }
    return { id: text(row, "id"), name: text(row, "name"), card_count: count };
  });
}

/** The caller's live deck [deckId], or null when it is not one: absent, deleted or another's. */
export async function readDeck(
  store: Store,
  deckId: string,
): Promise<Deck | null> {
  const found = await rows(
    store,
    `decks?select=id,name&id=eq.${deckId}&${own(store)}`,
  );
  const row = found[0];
  return row === undefined
    ? null
    : { id: text(row, "id"), name: text(row, "name") };
}

/** A stored card's id and sides, as the read tools describe them. */
export type StoredCard = {
  readonly id: string;
  readonly deck_id: string;
  readonly front: unknown;
  readonly back: unknown;
};

function storedCard(row: Record<string, unknown>): StoredCard {
  return {
    id: text(row, "id"),
    deck_id: text(row, "deck_id"),
    front: row.front,
    back: row.back,
  };
}

/** [limit] of a deck's live cards from [offset], oldest first, and how many it holds. */
export async function listCards(
  store: Store,
  deckId: string,
  offset: number,
  limit: number,
): Promise<{ cards: StoredCard[]; total: number }> {
  const response = await request(
    store,
    `cards?select=id,deck_id,front,back&deck_id=eq.${deckId}&${own(store)}` +
      `&order=created_at.asc,id.asc&limit=${limit}&offset=${offset}`,
    { prefer: "count=exact" },
  );
  const total = Number(response.headers.get("Content-Range")?.split("/")[1]);
  if (!Number.isInteger(total)) {
    throw new SupabaseError("the REST API answered no count");
  }
  const body: unknown = await response.json();
  if (!Array.isArray(body)) {
    throw new SupabaseError("the REST API answered without rows");
  }
  return { cards: body.map(storedCard), total };
}

/** Every live card of the caller's, with its deck. */
export async function allCards(store: Store): Promise<StoredCard[]> {
  return (await allRows(
    store,
    `cards?select=id,deck_id,front,back&${
      own(store)
    }&order=created_at.asc,id.asc`,
  )).map(storedCard);
}

/** Each live card's duplicate key in a deck, with the card's id. */
export async function deckKeys(
  store: Store,
  deckId: string,
): Promise<Map<string, string>> {
  const found = await allRows(
    store,
    `cards?select=id,card_key&deck_id=eq.${deckId}&${own(store)}&order=id.asc`,
  );
  return new Map(found.map((row) => [text(row, "card_key"), text(row, "id")]));
}

/** Inserts [rows] into [table] in one statement, so either all are stored or none is. */
export async function insert(
  store: Store,
  table: "decks" | "cards",
  rows: Record<string, unknown>[],
): Promise<void> {
  const response = await request(store, table, {
    method: "POST",
    body: rows,
    prefer: "return=minimal",
  });
  await response.body?.cancel();
}
