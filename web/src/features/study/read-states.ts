import "server-only";

import type { CardId } from "@/features/decks";
import { requestTimeoutMs, type ServerFailure } from "@/lib/supabase/failure";
import { field, parseTime } from "@/lib/supabase/row";
import { selectAll } from "@/lib/supabase/select-all";
import { createClient } from "@/lib/supabase/server";

import type { CardState, CardStates } from "./queue";

/**
 * The stored state of every card the signed-in user has reviewed, leaving out tombstoned
 * states, and the time they were read, which the queue rules count due cards at; or a server
 * failure, or `unreadable` for a row this version cannot read.
 */
export async function readCardStates(): Promise<
  { states: CardStates; readAt: number } | { failure: ServerFailure | "unreadable" }
> {
  const supabase = await createClient();
  const read = await selectAll((from, to) =>
    supabase
      .from("card_states")
      .select("card_id, stability, difficulty, last_review, due")
      .is("deleted_at", null)
      .order("card_id")
      .range(from, to)
      .abortSignal(AbortSignal.timeout(requestTimeoutMs)),
  );
  if ("failure" in read) return read;
  const states: CardStates = {};
  for (const row of read.rows) {
    const cardId = field(row, "card_id");
    const state = parseState(row);
    if (typeof cardId !== "string" || !state) return { failure: "unreadable" };
    states[cardId as CardId] = state;
  }
  return { states, readAt: Date.now() };
}

function parseState(row: unknown): CardState | null {
  const stability = field(row, "stability");
  const difficulty = field(row, "difficulty");
  const lastReview = parseTime(field(row, "last_review"));
  const due = parseTime(field(row, "due"));
  if (typeof stability !== "number" || typeof difficulty !== "number") return null;
  if (lastReview === null || due === null) return null;
  return { stability, difficulty, lastReview, due };
}
