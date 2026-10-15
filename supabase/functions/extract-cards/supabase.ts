/** The daily extraction count in `extraction_usage`. */

import {
  type SupabaseDeps,
  SupabaseError,
  type UserId,
} from "../_shared/auth.ts";

export const DAILY_EXTRACTION_LIMIT = 30;

/** Records one extraction for the user and returns true, or false when today's limit is reached. */
export async function consumeExtraction(
  userId: UserId,
  deps: SupabaseDeps,
): Promise<boolean> {
  const response = await deps.fetch(
    `${deps.url}/rest/v1/rpc/consume_extraction`,
    {
      method: "POST",
      headers: {
        apikey: deps.serviceRoleKey,
        Authorization: `Bearer ${deps.serviceRoleKey}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({
        user_id: userId,
        daily_limit: DAILY_EXTRACTION_LIMIT,
      }),
    },
  );
  if (!response.ok) {
    throw new SupabaseError(`consume_extraction answered ${response.status}`);
  }
  const allowed: unknown = await response.json();
  if (typeof allowed !== "boolean") {
    throw new SupabaseError("consume_extraction answered no boolean");
  }
  return allowed;
}
