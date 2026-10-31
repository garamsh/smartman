/** The caller's plan, prompt and photo count, through `public.begin_extraction`, and its outcome. */

import {
  type SupabaseDeps,
  SupabaseError,
  type UserId,
} from "../_shared/auth.ts";
import { type ModelId, modelId } from "./openrouter.ts";

/** A plan, as `private.plan_versions` names it. */
export type Plan = "free" | "pro" | "max";

/** The period a plan's photo limit counts over: a calendar month or a day in Asia/Seoul. */
export type Period = "month" | "day";

/** A saved prompt version: its id in `private.prompt_versions` and the instructions it holds. */
export type Prompt = { readonly versionId: number; readonly text: string };

/**
 * What one photo of the user may do: be extracted by its plan's model with the prompt the user is
 * served, recorded against the photo limit of the plan's version for its period; be refused at
 * that limit; or nothing, when the plan has no version, the active prompt is missing, or the
 * version names no model the function would call.
 */
export type Start =
  | {
    readonly kind: "allowed";
    /** The `extraction_usage` row recorded for the photo, which names its call record. */
    readonly usageId: number;
    readonly plan: Plan;
    readonly model: ModelId;
    readonly prompt: Prompt;
  }
  | {
    readonly kind: "rate_limited";
    readonly plan: Plan;
    readonly photoLimit: number;
    readonly period: Period;
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
 * set) and, under the photo limit of the plan's version, records the photo with what serves it.
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
    photo_limit: photoLimit,
    period,
    allowed,
    prompt_version_id: versionId,
    prompt,
    usage_id: usageId,
  } = row as Record<string, unknown>;
  if (
    (plan !== "free" && plan !== "pro" && plan !== "max") ||
    (period !== "month" && period !== "day") ||
    typeof allowed !== "boolean" || typeof photoLimit !== "number" ||
    typeof versionId !== "number" || !Number.isSafeInteger(versionId) ||
    typeof prompt !== "string"
  ) {
    throw new SupabaseError("begin_extraction answered a row it should not");
  }
  if (!allowed) return { kind: "rate_limited", plan, photoLimit, period };
  if (typeof usageId !== "number" || !Number.isSafeInteger(usageId)) {
    throw new SupabaseError(
      "begin_extraction allowed a photo it did not record",
    );
  }
  const id = typeof model === "string" ? modelId(model) : null;
  return id === null ? { kind: "not_configured" } : {
    kind: "allowed",
    usageId,
    plan,
    model: id,
    prompt: { versionId, text: prompt },
  };
}

/** How a counted photo's model calls failed, each attempt's kind in `Finish.failures`. */
export type AttemptFailure = "invalid_output" | "model_error" | "timeout";

/**
 * How a counted photo's extraction ended (ADR 0130): its outcome, its model calls, the failure of
 * each that failed, the request's milliseconds until then, and the last reply's cards answered and
 * dropped.
 */
export type Finish = {
  readonly outcome: "ok" | "no_cards" | "invalid_output" | "model_error";
  readonly attempts: 1 | 2;
  readonly latencyMs: number;
  readonly cardsReturned: number;
  readonly cardsDropped: number;
  readonly failures: readonly AttemptFailure[];
};

/**
 * Records [finish] on the call record of [usageId], through `public.finish_extraction`, answering
 * whether it was recorded. The record is telemetry: its failure never decides the photo's answer.
 */
export async function finishExtraction(
  usageId: number,
  finish: Finish,
  deps: SupabaseDeps,
): Promise<boolean> {
  const response = await deps.fetch(
    `${deps.url}/rest/v1/rpc/finish_extraction`,
    {
      method: "POST",
      headers: {
        apikey: deps.serviceRoleKey,
        Authorization: `Bearer ${deps.serviceRoleKey}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({
        usage_id: usageId,
        outcome: finish.outcome,
        attempts: finish.attempts,
        latency_ms: Math.round(finish.latencyMs),
        cards_returned: finish.cardsReturned,
        cards_dropped: finish.cardsDropped,
        failures: finish.failures,
      }),
    },
  ).catch(() => null);
  return response?.ok ?? false;
}
