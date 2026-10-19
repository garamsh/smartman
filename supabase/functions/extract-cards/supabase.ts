/** The caller's plan, prompt and daily count, through `public.begin_extraction`. */

import {
  type SupabaseDeps,
  SupabaseError,
  type UserId,
} from "../_shared/auth.ts";
import { type ModelId, modelId } from "./openrouter.ts";

/** A plan, as `private.plans` names it. */
export type Plan = "free" | "pro" | "special";

/** A saved prompt version: its id in `private.prompt_versions` and the instructions it holds. */
export type Prompt = { readonly versionId: number; readonly text: string };

/**
 * What one photo of the user may do: be extracted by its plan's model with the prompt the user is
 * served, recorded against the plan's daily limit; be refused at that limit; or nothing, when the
 * plan's settings or the active prompt are missing, or the plan names no model the function would
 * call.
 */
export type Start =
  | {
    readonly kind: "allowed";
    readonly plan: Plan;
    readonly model: ModelId;
    readonly prompt: Prompt;
  }
  | {
    readonly kind: "rate_limited";
    readonly plan: Plan;
    readonly dailyLimit: number;
  }
  | { readonly kind: "not_configured" };

/** Whether an admin suspended the user (`public.user_suspended`); a suspended user extracts nothing. */
export async function userSuspended(
  userId: UserId,
  deps: SupabaseDeps,
): Promise<boolean> {
  const response = await deps.fetch(
    `${deps.url}/rest/v1/rpc/user_suspended`,
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
    throw new SupabaseError(`user_suspended answered ${response.status}`);
  }
  const suspended: unknown = await response.json();
  if (typeof suspended !== "boolean") {
    throw new SupabaseError("user_suspended answered no boolean");
  }
  return suspended;
}

/**
 * Resolves the user's plan and prompt (ADR 0073: an admin is served the test version when one is
 * set) and, under the plan's daily limit, records the photo with what serves it.
 */
export async function beginExtraction(
  userId: UserId,
  deps: SupabaseDeps,
): Promise<Start> {
  const response = await deps.fetch(
    `${deps.url}/rest/v1/rpc/begin_extraction`,
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
    throw new SupabaseError(`begin_extraction answered ${response.status}`);
  }
  const rows: unknown = await response.json();
  if (!Array.isArray(rows)) {
    throw new SupabaseError("begin_extraction answered no rows");
  }
  if (rows.length === 0) return { kind: "not_configured" };
  const row: unknown = rows[0];
  if (typeof row !== "object" || row === null) {
    throw new SupabaseError("begin_extraction answered a row that is not one");
  }
  const {
    plan,
    model,
    daily_limit: dailyLimit,
    allowed,
    prompt_version_id: versionId,
    prompt,
  } = row as Record<string, unknown>;
  if (
    (plan !== "free" && plan !== "pro" && plan !== "special") ||
    typeof allowed !== "boolean" || typeof dailyLimit !== "number" ||
    typeof versionId !== "number" || !Number.isSafeInteger(versionId) ||
    typeof prompt !== "string"
  ) {
    throw new SupabaseError("begin_extraction answered a row it should not");
  }
  if (!allowed) return { kind: "rate_limited", plan, dailyLimit };
  const id = typeof model === "string" ? modelId(model) : null;
  return id === null ? { kind: "not_configured" } : {
    kind: "allowed",
    plan,
    model: id,
    prompt: { versionId, text: prompt },
  };
}
