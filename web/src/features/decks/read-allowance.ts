"use server";

import { createClient } from "@/supabase/server";
import { readUserId } from "@/supabase/session";
import { field } from "@/supabase/row";
import { requestTimeoutMs } from "@/supabase/failure";

/** The current plan's period and remaining photos, or unknown while the read fails. */
export type Allowance = { remaining: number; limit: number; period: "day" | "month" };
/** Reads the same allowance as the phone; the extraction function enforces the quota. */
export async function readAllowance(): Promise<Allowance | null> {
  const client = await createClient();
  if ("failure" in (await readUserId(client))) return null;
  const result = await client
    .rpc("extraction_allowance")
    .abortSignal(AbortSignal.timeout(requestTimeoutMs));
  const row: unknown = Array.isArray(result.data) ? result.data[0] : null;
  const limit = field(row, "photo_limit");
  const used = field(row, "used");
  const period = field(row, "period");
  if (
    result.error ||
    typeof limit !== "number" ||
    !Number.isInteger(limit) ||
    limit < 0 ||
    typeof used !== "number" ||
    !Number.isInteger(used) ||
    used < 0 ||
    (period !== "day" && period !== "month")
  )
    return null;
  return { remaining: Math.max(0, limit - used), limit, period };
}
