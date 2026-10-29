"use server";

import { revalidatePath } from "next/cache";
import { createClient } from "@/supabase/server";
import { readUserId } from "@/supabase/session";
import { selectAll } from "@/supabase/select-all";
import { requestTimeoutMs } from "@/supabase/failure";
import { field } from "@/supabase/row";
import { cardKey, parseDraft } from "./authoring";
import { parseContent } from "./card-content";
import { parseCardId, parseDeckId } from "./library";

/**
 * A duplicate warning stores nothing and names the stored or earlier card it repeats and the
 * index of the input card that repeats it; a failed save leaves the caller's draft intact.
 */
export type SaveCardsResult =
  { saved: true } | { saved: false; message: string; duplicate?: string; at?: number };
/** Inserts explicit reviewed cards under the current owner, using stable ids for safe retries. */
export async function saveCards(
  deckId: string,
  input: unknown,
  source: "manual" | "import",
  allowDuplicate = false,
): Promise<SaveCardsResult> {
  const malformed = { saved: false as const, message: "카드 내용을 확인해 주세요" };
  if (
    !parseDeckId(deckId) ||
    !Array.isArray(input) ||
    input.length < 1 ||
    input.length > 100 ||
    !["manual", "import"].includes(source) ||
    typeof allowDuplicate !== "boolean" ||
    !boundedJson(input)
  )
    return malformed;
  const cards = input.map(parseDraft);
  if (cards.some((card) => !card || !parseCardId(card.id))) return malformed;
  const client = await createClient();
  const session = await readUserId(client);
  if ("failure" in session) return { saved: false, message: "다시 로그인해 주세요" };
  const { userId } = session;
  const deck = await client
    .from("decks")
    .select("id")
    .eq("id", deckId)
    .eq("user_id", userId)
    .is("deleted_at", null)
    .abortSignal(AbortSignal.timeout(requestTimeoutMs));
  if (deck.error || !Array.isArray(deck.data) || deck.data.length !== 1)
    return { saved: false, message: "덱을 찾을 수 없어요. 추가할 덱을 다시 골라 주세요." };
  const existing = await selectAll((from, to, counted) =>
    client
      .from("cards")
      .select("id,card_key", counted ? { count: "exact" } : {})
      .eq("deck_id", deckId)
      .eq("user_id", userId)
      .is("deleted_at", null)
      .order("id")
      .range(from, to)
      .abortSignal(AbortSignal.timeout(requestTimeoutMs)),
  );
  if ("failure" in existing)
    return { saved: false, message: "카드를 저장하지 못했어요. 다시 시도해 주세요." };
  const now = new Date().toISOString();
  const rows = [];
  const keys = new Map(
    existing.rows.flatMap((row) => {
      const key = field(row, "card_key");
      const id = field(row, "id");
      return typeof key === "string" && typeof id === "string" ? [[key, id] as const] : [];
    }),
  );
  const seenIds = new Set<string>();
  for (const [at, card] of cards.entries()) {
    if (!card || seenIds.has(card.id)) return malformed;
    seenIds.add(card.id);
    const front = parseContent(card.front);
    if (!front) return malformed;
    const key = cardKey(front);
    const duplicate = keys.get(key);
    if (!allowDuplicate && duplicate && duplicate !== card.id)
      return { saved: false, message: "이 덱에 이미 있는 카드예요", duplicate, at };
    keys.set(key, card.id);
    rows.push({
      ...card,
      deck_id: deckId,
      user_id: userId,
      card_key: key,
      source,
      template: "free",
      template_version: 1,
      created_at: now,
      updated_at: now,
    });
  }
  const write = await client
    .from("cards")
    .upsert(rows, { onConflict: "id", ignoreDuplicates: true })
    .abortSignal(AbortSignal.timeout(requestTimeoutMs));
  if (write.error)
    return { saved: false, message: "카드를 저장하지 못했어요. 다시 시도해 주세요." };
  const persisted = await client
    .from("cards")
    .select("id,deck_id,front,back")
    .eq("user_id", userId)
    .eq("deck_id", deckId)
    .is("deleted_at", null)
    .in(
      "id",
      rows.map((row) => row.id),
    )
    .abortSignal(AbortSignal.timeout(requestTimeoutMs));
  if (
    persisted.error ||
    !Array.isArray(persisted.data) ||
    !rows.every((row) =>
      persisted.data.some(
        (saved: unknown) =>
          field(saved, "id") === row.id &&
          JSON.stringify(parseContent(field(saved, "front"))) ===
            JSON.stringify(parseContent(row.front)) &&
          JSON.stringify(parseContent(field(saved, "back"))) ===
            JSON.stringify(parseContent(row.back)),
      ),
    )
  )
    return { saved: false, message: "카드를 저장하지 못했어요. 다시 시도해 주세요." };
  revalidatePath("/", "layout");
  return { saved: true };
}

function boundedJson(value: unknown): boolean {
  try {
    return JSON.stringify(value).length <= 1_000_000;
  } catch {
    return false;
  }
}
