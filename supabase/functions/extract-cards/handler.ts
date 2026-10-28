/** The extract-cards request pipeline and the mapping from each outcome to an HTTP status. */

import type { Card } from "./cards.ts";
import type { Config } from "./config.ts";
import { type Attempt, extractCards } from "./openrouter.ts";
import { parseRequest } from "./request.ts";
import { authenticate, type UserId } from "../_shared/auth.ts";
import {
  beginExtraction,
  type Period,
  type Plan,
  userSuspended,
} from "./supabase.ts";

/** How a request ended; the error body carries the same code, for the app to show. */
export type Outcome =
  | "ok"
  | "method_not_allowed"
  | "not_configured"
  | "unauthenticated"
  | "suspended"
  | "bad_request"
  | "too_large"
  | "unsupported_type"
  | "rate_limited"
  | "no_cards"
  | "model_error"
  | "internal";

/**
 * The one line logged per request. It carries these fields only: never the image, the
 * cards, the token, or a configuration value.
 */
export type LogEntry = {
  readonly user_id: UserId | null;
  /** The caller's plan, or null when it was not read. */
  readonly plan: Plan | null;
  /** The model of the call made, or null when none was. */
  readonly model: string | null;
  /** The id of the prompt version the call was made with, or null when none was made. */
  readonly prompt_version: number | null;
  readonly latency_ms: number;
  /** The call's usage; null when it made none or reported none. */
  readonly prompt_tokens: number | null;
  readonly completion_tokens: number | null;
  /** The reply's cards dropped for breaking a rule; null when no reply was read as the schema's. */
  readonly dropped_cards: number | null;
  readonly outcome: Outcome;
};

export type HandlerDeps = {
  readonly config: Config;
  readonly fetch: typeof fetch;
  readonly log: (entry: LogEntry) => void;
  /** Milliseconds from a monotonic clock. */
  readonly now: () => number;
};

export function status(outcome: Outcome): number {
  switch (outcome) {
    case "ok":
      return 200;
    case "bad_request":
      return 400;
    case "unauthenticated":
      return 401;
    case "suspended":
      return 403;
    case "method_not_allowed":
      return 405;
    case "too_large":
      return 413;
    case "unsupported_type":
      return 415;
    case "no_cards":
      return 422;
    case "rate_limited":
      return 429;
    case "internal":
      return 500;
    case "model_error":
      return 502;
    case "not_configured":
      return 503;
  }
}

type Result = {
  readonly outcome: Outcome;
  readonly userId: UserId | null;
  readonly plan?: Plan;
  readonly promptVersion?: number;
  /** The photo limit and its period, which a `rate_limited` answer states. */
  readonly limit?: { readonly photos: number; readonly period: Period };
  readonly attempts: readonly Attempt[];
  readonly cards?: readonly Card[];
  /** How many of the reply's cards were dropped, when a reply was read as the schema's. */
  readonly dropped?: number;
};

export function createHandler(
  deps: HandlerDeps,
): (request: Request) => Promise<Response> {
  return async (request) => {
    const started = deps.now();
    let result: Result;
    try {
      result = await handle(request, deps);
    } catch (error) {
      log(deps, started, { outcome: "internal", userId: null, attempts: [] });
      throw error;
    }
    log(deps, started, result);
    const body = result.outcome === "ok"
      ? { cards: result.cards }
      : result.outcome === "rate_limited"
      ? {
        error: result.outcome,
        photo_limit: result.limit?.photos,
        period: result.limit?.period,
      }
      : { error: result.outcome };
    return Response.json(body, { status: status(result.outcome) });
  };
}

async function handle(request: Request, deps: HandlerDeps): Promise<Result> {
  const refused = (outcome: Outcome, userId: UserId | null = null): Result => ({
    outcome,
    userId,
    attempts: [],
  });
  if (request.method !== "POST") return refused("method_not_allowed");
  const config = deps.config;
  if (config.kind === "not_configured") return refused("not_configured");

  const supabase = {
    url: config.supabaseUrl,
    serviceRoleKey: config.serviceRoleKey,
    fetch: deps.fetch,
  };
  const userId = await authenticate(
    request.headers.get("Authorization"),
    supabase,
  );
  if (userId === null) return refused("unauthenticated");

  const parsed = await parseRequest(request.body);
  if (!parsed.ok) return refused(parsed.failure, userId);
  if (await userSuspended(userId, supabase)) {
    return refused("suspended", userId);
  }
  const start = await beginExtraction(userId, supabase);
  if (start.kind === "not_configured") return refused("not_configured", userId);
  if (start.kind === "rate_limited") {
    return {
      outcome: "rate_limited",
      userId,
      plan: start.plan,
      limit: { photos: start.photoLimit, period: start.period },
      attempts: [],
    };
  }
  const plan = start.plan;
  const promptVersion = start.prompt.versionId;

  const extraction = await extractCards(
    parsed.request.image,
    parsed.request.languages,
    start.model,
    start.prompt.text,
    {
      apiKey: config.openRouterApiKey,
      fetch: deps.fetch,
      now: deps.now,
    },
  );
  switch (extraction.kind) {
    case "cards":
      return {
        outcome: "ok",
        userId,
        plan,
        promptVersion,
        attempts: extraction.attempts,
        cards: extraction.cards,
        dropped: extraction.dropped.length,
      };
    case "no_cards":
      return {
        outcome: "no_cards",
        userId,
        plan,
        promptVersion,
        attempts: extraction.attempts,
        dropped: 0,
      };
    case "invalid_output":
      return {
        outcome: "model_error",
        userId,
        plan,
        promptVersion,
        attempts: extraction.attempts,
        ...(extraction.dropped.length === 0
          ? {}
          : { dropped: extraction.dropped.length }),
      };
    case "model_error":
      return {
        outcome: "model_error",
        userId,
        plan,
        promptVersion,
        attempts: extraction.attempts,
      };
  }
}

function log(deps: HandlerDeps, started: number, result: Result): void {
  const usages = result.attempts.flatMap((attempt) =>
    attempt.usage === null ? [] : [attempt.usage]
  );
  const sum = (pick: (usage: (typeof usages)[number]) => number) =>
    usages.length === 0
      ? null
      : usages.reduce((total, usage) => total + pick(usage), 0);
  deps.log({
    user_id: result.userId,
    plan: result.plan ?? null,
    model: result.attempts.at(-1)?.model ?? null,
    prompt_version: result.promptVersion ?? null,
    latency_ms: Math.round(deps.now() - started),
    prompt_tokens: sum((usage) => usage.promptTokens),
    completion_tokens: sum((usage) => usage.completionTokens),
    dropped_cards: result.dropped ?? null,
    outcome: result.outcome,
  });
}
