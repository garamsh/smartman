/** The caller's plan, prompt and photo count, through `public.begin_extraction`, and its outcome. */

import {
  type SupabaseDeps,
  SupabaseError,
  type UserId,
} from "../_shared/auth.ts";
import type { CursorToken } from "./continuation.ts";
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
 * How a counted photo's extraction ended (ADR 0130): its outcome, its first read's model calls and
 * the failure of each that failed, the request's milliseconds until then, the cards answered and
 * the replies' cards dropped, and whether the page was left unread past the cards answered (ADR
 * 0135, ADR 0138). `continuations` counts the calls that read on after a cut reply, and `cursor` is
 * the token a later request goes on with, null when the page is done.
 */
export type Finish = {
  readonly outcome: "ok" | "no_cards" | "invalid_output" | "model_error";
  readonly attempts: 1 | 2;
  readonly latencyMs: number;
  readonly cardsReturned: number;
  readonly cardsDropped: number;
  readonly failures: readonly AttemptFailure[];
  readonly truncated: boolean;
  readonly continuations: number;
  readonly cursor: CursorToken | null;
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
        truncated: finish.truncated,
        continuations: finish.continuations,
        cursor: finish.cursor,
      }),
    },
  ).catch(() => null);
  return response?.ok ?? false;
}

/**
 * A photo a cursor goes on with (ADR 0138): its usage row, the plan, model and prompt version that
 * served its first read, and the cards and continuing calls it has had; or `refused`, when the
 * cursor is unknown, used, expired or another user's.
 */
export type Resume =
  | {
    readonly kind: "resumed";
    readonly usageId: number;
    readonly plan: Plan;
    readonly model: ModelId;
    readonly prompt: Prompt;
    readonly cardsRead: number;
    readonly continuations: number;
  }
  | { readonly kind: "refused" }
  | { readonly kind: "not_configured" };

/** Takes [token] for [userId] through `public.resume_extraction`, so it cannot be taken again. */
export async function resumeExtraction(
  userId: UserId,
  token: CursorToken,
  deps: SupabaseDeps,
): Promise<Resume> {
  const response = await deps.fetch(
    `${deps.url}/rest/v1/rpc/resume_extraction`,
    {
      method: "POST",
      headers: {
        apikey: deps.serviceRoleKey,
        Authorization: `Bearer ${deps.serviceRoleKey}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({ user_id: userId, cursor: token }),
    },
  );
  if (!response.ok) {
    throw new SupabaseError(`resume_extraction answered ${response.status}`);
  }
  const rows: unknown = await response.json();
  if (!Array.isArray(rows)) {
    throw new SupabaseError("resume_extraction answered no rows");
  }
  if (rows.length === 0) return { kind: "refused" };
  const row: unknown = rows[0];
  if (typeof row !== "object" || row === null) {
    throw new SupabaseError("resume_extraction answered a row that is not one");
  }
  const {
    usage_id: usageId,
    plan,
    model,
    prompt_version_id: versionId,
    prompt,
    cards_read: cardsRead,
    continuations,
  } = row as Record<string, unknown>;
  if (
    (plan !== "free" && plan !== "pro" && plan !== "max") ||
    !isCount(usageId) || !isCount(versionId) || typeof prompt !== "string" ||
    !isCount(cardsRead) || !isCount(continuations)
  ) {
    throw new SupabaseError("resume_extraction answered a row it should not");
  }
  const id = typeof model === "string" ? modelId(model) : null;
  return id === null ? { kind: "not_configured" } : {
    kind: "resumed",
    usageId,
    plan,
    model: id,
    prompt: { versionId, text: prompt },
    cardsRead,
    continuations,
  };
}

/**
 * How a request that went on with a cursor read: its continuing calls, the cards it answered,
 * whether the page is still unread past them, and the next cursor, null when the page is done.
 */
export type Resumed = {
  readonly continuations: number;
  readonly cardsReturned: number;
  readonly truncated: boolean;
  readonly cursor: CursorToken | null;
};

/**
 * Adds [resumed] to the call record of [usageId], through `public.record_resumed_extraction`,
 * answering whether it was recorded. Like `finishExtraction`, it never decides the answer.
 */
export async function recordResumed(
  usageId: number,
  resumed: Resumed,
  deps: SupabaseDeps,
): Promise<boolean> {
  const response = await deps.fetch(
    `${deps.url}/rest/v1/rpc/record_resumed_extraction`,
    {
      method: "POST",
      headers: {
        apikey: deps.serviceRoleKey,
        Authorization: `Bearer ${deps.serviceRoleKey}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({
        usage_id: usageId,
        continuations: resumed.continuations,
        cards_returned: resumed.cardsReturned,
        truncated: resumed.truncated,
        cursor: resumed.cursor,
      }),
    },
  ).catch(() => null);
  return response?.ok ?? false;
}

function isCount(value: unknown): value is number {
  return typeof value === "number" && Number.isSafeInteger(value) && value >= 0;
}
