/** The caller's plan and its daily count, through `public.start_extraction`. */

import {
  type SupabaseDeps,
  SupabaseError,
  type UserId,
} from "../_shared/auth.ts";
import { type ModelId, modelId } from "./openrouter.ts";

/** A plan, as `private.plans` names it. */
export type Plan = "free" | "pro" | "special";

/**
 * What one photo of the user may do: be extracted by its plan's model, recorded against the
 * plan's daily limit; be refused at that limit; or nothing, when the plan's settings are missing
 * or name no model the function would call.
 */
export type Start =
  | { readonly kind: "allowed"; readonly plan: Plan; readonly model: ModelId }
  | {
    readonly kind: "rate_limited";
    readonly plan: Plan;
    readonly dailyLimit: number;
  }
  | { readonly kind: "not_configured" };

/** Resolves the user's plan and, under its daily limit, records the photo. */
export async function startExtraction(
  userId: UserId,
  deps: SupabaseDeps,
): Promise<Start> {
  const response = await deps.fetch(
    `${deps.url}/rest/v1/rpc/start_extraction`,
    {
      method: "POST",
      headers: {
        apikey: deps.serviceRoleKey,
        Authorization: `Bearer ${deps.serviceRoleKey}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({ user_id: userId }),
    },
  );
  if (!response.ok) {
    throw new SupabaseError(`start_extraction answered ${response.status}`);
  }
  const rows: unknown = await response.json();
  if (!Array.isArray(rows)) {
    throw new SupabaseError("start_extraction answered no rows");
  }
  if (rows.length === 0) return { kind: "not_configured" };
  const row: unknown = rows[0];
  if (typeof row !== "object" || row === null) {
    throw new SupabaseError("start_extraction answered a row that is not one");
  }
  const { plan, model, daily_limit: dailyLimit, allowed } = row as Record<
    string,
    unknown
  >;
  if (
    (plan !== "free" && plan !== "pro" && plan !== "special") ||
    typeof allowed !== "boolean" || typeof dailyLimit !== "number"
  ) {
    throw new SupabaseError("start_extraction answered a row it should not");
  }
  if (!allowed) return { kind: "rate_limited", plan, dailyLimit };
  const id = typeof model === "string" ? modelId(model) : null;
  return id === null
    ? { kind: "not_configured" }
    : { kind: "allowed", plan, model: id };
}
