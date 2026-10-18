/** The extract-cards request pipeline and the mapping from each outcome to an HTTP status. */

import type { Card } from "./cards.ts";
import type { Config } from "./config.ts";
import { issueToken, verifyToken } from "./conversation.ts";
import { type Attempt, extractCards, surveyPage } from "./openrouter.ts";
import { parseRequest } from "./request.ts";
import type { Survey } from "./survey.ts";
import { authenticate, type UserId } from "../_shared/auth.ts";
import { consumeExtraction } from "./supabase.ts";

/** How a request ended; the error body carries the same code, for the app to show. */
export type Outcome =
  | "ok"
  | "method_not_allowed"
  | "not_configured"
  | "unauthenticated"
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
  /** The model of the last call made, or null when none was. */
  readonly model: string | null;
  readonly latency_ms: number;
  /** Summed over the calls made; null when none reported usage. */
  readonly prompt_tokens: number | null;
  readonly completion_tokens: number | null;
  readonly outcome: Outcome;
};

export type HandlerDeps = {
  readonly config: Config;
  readonly fetch: typeof fetch;
  readonly log: (entry: LogEntry) => void;
  /** Milliseconds from a monotonic clock. */
  readonly now: () => number;
  /** The wall clock, in milliseconds since the epoch, for a conversation's expiry. */
  readonly clock: () => number;
};

export function status(outcome: Outcome): number {
  switch (outcome) {
    case "ok":
      return 200;
    case "bad_request":
      return 400;
    case "unauthenticated":
      return 401;
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
  readonly attempts: readonly Attempt[];
  readonly cards?: readonly Card[];
  readonly survey?: { readonly survey: Survey; readonly conversation: string };
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
    const body = result.outcome !== "ok"
      ? { error: result.outcome }
      : result.survey === undefined
      ? { cards: result.cards }
      : { conversation: result.survey.conversation, ...result.survey.survey };
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
  const { image, languages, mode } = parsed.request;
  // A survey always counts. Cards made after one, on the same photo within its token's life,
  // count nothing more: the conversation counted once.
  const conversation = mode.kind === "survey" ||
      parsed.request.conversation === null
    ? null
    : await verifyToken(
      config.serviceRoleKey,
      parsed.request.conversation,
      userId,
      image,
      deps.clock(),
    );
  if (
    conversation === null && !await consumeExtraction(userId, supabase)
  ) {
    return refused("rate_limited", userId);
  }
  const call = {
    apiKey: config.openRouterApiKey,
    fetch: deps.fetch,
    now: deps.now,
  };

  if (mode.kind === "survey") {
    const model = config.surveyModel;
    const result = await surveyPage(
      image,
      languages,
      { primary: model, retry: model },
      call,
    );
    if (result.kind !== "survey") {
      return {
        outcome: result.kind === "no_cards" ? "no_cards" : "model_error",
        userId,
        attempts: result.attempts,
      };
    }
    const vocabulary = result.survey.groups.every((group) =>
      group.kind === "vocabulary"
    );
    return {
      outcome: "ok",
      userId,
      attempts: result.attempts,
      survey: {
        survey: result.survey,
        conversation: await issueToken(
          config.serviceRoleKey,
          userId,
          image,
          vocabulary,
          deps.clock(),
        ),
      },
    };
  }

  const plan = mode.kind === "plan" ? mode.plan : null;
  // A page of vocabulary alone, as its survey found it, is made on the vocabulary model; a
  // topic the user typed may be anything, so it keeps the card model.
  const vocabularyPage = plan !== null && conversation?.vocabulary === true &&
    plan.added.length === 0;
  const extraction = await extractCards(
    image,
    languages,
    vocabularyPage
      ? { primary: config.vocabularyModel, retry: config.models.retry }
      : config.models,
    call,
    plan,
  );
  switch (extraction.kind) {
    case "cards":
      return {
        outcome: "ok",
        userId,
        attempts: extraction.attempts,
        cards: extraction.cards,
      };
    case "no_cards":
      return { outcome: "no_cards", userId, attempts: extraction.attempts };
    case "invalid_output":
    case "model_error":
      return { outcome: "model_error", userId, attempts: extraction.attempts };
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
    model: result.attempts.at(-1)?.model ?? null,
    latency_ms: Math.round(deps.now() - started),
    prompt_tokens: sum((usage) => usage.promptTokens),
    completion_tokens: sum((usage) => usage.completionTokens),
    outcome: result.outcome,
  });
}
