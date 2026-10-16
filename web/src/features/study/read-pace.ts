import "server-only";

import { classifyFailure, requestTimeoutMs, type ServerFailure } from "@/supabase/failure";
import { field } from "@/supabase/row";
import { createClient } from "@/supabase/server";
import { readUserId } from "@/supabase/session";

/** How many of the latest reviews the pace is the median of, as on the phone. */
export const paceWindow = 200;

/** The fewest reviews a pace is read from. */
export const paceMinimum = 20;

/** The time one card is taken to need while the user's own pace is unknown, in milliseconds. */
export const defaultPerCardMs = 10_000;

/**
 * How long the signed-in user takes over one card, in milliseconds: the median time of their
 * latest [paceWindow] reviews, or [defaultPerCardMs] while they have fewer than [paceMinimum];
 * or a server failure, or `unreadable` for a row this version cannot read.
 */
export async function readPace(): Promise<
  { perCardMs: number } | { failure: ServerFailure | "unreadable" }
> {
  const supabase = await createClient();
  const session = await readUserId(supabase);
  if ("failure" in session) return session;
  const { data, error, status } = await supabase
    .from("reviews")
    .select("duration_ms")
    .eq("user_id", session.userId)
    .is("deleted_at", null)
    .order("reviewed_at", { ascending: false })
    .limit(paceWindow)
    .abortSignal(AbortSignal.timeout(requestTimeoutMs));
  if (error) return { failure: classifyFailure(error, status) };
  const durations: number[] = [];
  for (const row of data) {
    const duration = field(row, "duration_ms");
    if (typeof duration !== "number") return { failure: "unreadable" };
    durations.push(duration);
  }
  if (durations.length < paceMinimum) return { perCardMs: defaultPerCardMs };
  durations.sort((a, b) => a - b);
  // The middle one, or the two middle ones of an even count, averaged and rounded down.
  const middle = Math.floor(durations.length / 2);
  const centre = durations.slice(durations.length % 2 === 1 ? middle : middle - 1, middle + 1);
  return { perCardMs: Math.floor(centre.reduce((sum, value) => sum + value, 0) / centre.length) };
}

/** The whole minutes [cards] cards take at [perCardMs] each, rounded up. */
export function sessionMinutes(cards: number, perCardMs: number): number {
  return Math.ceil((cards * perCardMs) / 60_000);
}
