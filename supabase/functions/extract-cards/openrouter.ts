/** Extracts cards from an image through one OpenRouter chat completion. */

import {
  type Card,
  type CardRule,
  cardsSchema,
  composeInstructions,
  parseReply,
} from "./cards.ts";
import { userPrompt } from "./prompt_v8.ts";
import type { Image, LanguageHints } from "./request.ts";

export const OPENROUTER_URL = "https://openrouter.ai/api/v1/chat/completions";
// Bounds one call's cost; a reply cut off at it fails the schema.
export const MAX_OUTPUT_TOKENS = 16384;
/**
 * How long one model call may take, its reply's body included, before it is abandoned as a model
 * error: four times the p90 of 15.6 s measured on 2026-10-28, under the Edge Function's 150 s
 * request idle timeout and wall clock (ADR 0124).
 */
export const MODEL_TIMEOUT_MS = 60_000;

/** An OpenRouter model ID, such as `anthropic/claude-haiku-5.5`. */
export type ModelId = string & { readonly __brand: "ModelId" };

export function modelId(value: string): ModelId | null {
  return /^[\w.-]+\/[\w.:-]+$/.test(value) ? value as ModelId : null;
}

/**
 * What OpenRouter reported for one call; `costUsd` is null when it reported no cost, and
 * otherwise the call's whole price: OpenRouter's `cost` plus the provider's `upstream_inference_cost`.
 */
export type Usage = {
  readonly promptTokens: number;
  readonly completionTokens: number;
  readonly costUsd: number | null;
};

/**
 * One model call: the model, how long it took, its usage when the reply carried one, and whether
 * it was abandoned at its timeout.
 */
export type Attempt = {
  readonly model: ModelId;
  readonly latencyMs: number;
  readonly usage: Usage | null;
  readonly timedOut: boolean;
};

/**
 * How a call ended. `dropped` names the rule each dropped card broke: on `cards`, the cards the
 * reply returned beside those kept; on `invalid_output`, every card of a reply that kept none.
 */
export type Extraction =
  | {
    readonly kind: "cards";
    readonly cards: readonly Card[];
    readonly dropped: readonly CardRule[];
    readonly attempts: readonly Attempt[];
  }
  | { readonly kind: "no_cards"; readonly attempts: readonly Attempt[] }
  | {
    readonly kind: "invalid_output";
    readonly dropped: readonly CardRule[];
    readonly attempts: readonly Attempt[];
  }
  | { readonly kind: "model_error"; readonly attempts: readonly Attempt[] };

export type ExtractDeps = {
  readonly apiKey: string;
  readonly fetch: typeof fetch;
  /** Milliseconds from a monotonic clock. */
  readonly now: () => number;
  /** How long the call may take before it is a model error, `MODEL_TIMEOUT_MS` when deployed. */
  readonly timeoutMs: number;
};

/**
 * One call to [model] with [prompt] and then the output contract as the system prompt. A card that
 * breaks a rule is dropped; output that is not the schema's, or whose every card is dropped, is
 * `invalid_output`, with no second call.
 */
export async function extractCards(
  image: Image,
  languages: LanguageHints,
  model: ModelId,
  prompt: string,
  deps: ExtractDeps,
): Promise<Extraction> {
  const call = await callModel(
    model,
    composeInstructions(prompt),
    image,
    languages,
    deps,
  );
  const attempts = [call.attempt];
  if (call.reply === null) return { kind: "model_error", attempts };
  const parsed = parseReply(call.reply);
  if (parsed === null) {
    return { kind: "invalid_output", dropped: [], attempts };
  }
  const { cards, dropped } = parsed;
  if (cards.length > 0) return { kind: "cards", cards, dropped, attempts };
  return dropped.length === 0
    ? { kind: "no_cards", attempts }
    : { kind: "invalid_output", dropped, attempts };
}

type Call = { readonly attempt: Attempt; readonly reply: string | null };

/** Sends one request; `reply` is the message text, or null when the call itself failed. */
async function callModel(
  model: ModelId,
  instructions: string,
  image: Image,
  languages: LanguageHints,
  deps: ExtractDeps,
): Promise<Call> {
  const started = deps.now();
  const controller = new AbortController();
  let timer: ReturnType<typeof setTimeout> | undefined;
  // Settles when the deadline passes, aborting the request; a fetch that ignores the abort is
  // still left behind.
  const deadline = new Promise<"timed_out">((resolve) => {
    timer = setTimeout(() => {
      controller.abort();
      resolve("timed_out");
    }, deps.timeoutMs);
  });
  const read = async (): Promise<Read> => {
    const response = await deps.fetch(OPENROUTER_URL, {
      method: "POST",
      signal: controller.signal,
      headers: {
        "Authorization": `Bearer ${deps.apiKey}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({
        model,
        messages: [
          { role: "system", content: instructions },
          {
            role: "user",
            content: [
              { type: "text", text: userPrompt(languages) },
              {
                type: "image_url",
                image_url: { url: `data:${image.type};base64,${image.base64}` },
              },
            ],
          },
        ],
        response_format: {
          type: "json_schema",
          json_schema: { name: "cards", strict: true, schema: cardsSchema },
        },
        // Route only to providers that honour the schema rather than ignore it.
        provider: { require_parameters: true },
        max_tokens: MAX_OUTPUT_TOKENS,
      }),
    });
    const body: unknown = await response.json().catch(() => null);
    return { ok: response.ok, body };
  };
  let result: Read | "failed" | "timed_out";
  try {
    result = await Promise.race([read(), deadline]);
  } catch {
    result = "failed";
  } finally {
    clearTimeout(timer);
  }
  const latencyMs = deps.now() - started;
  if (result === "failed" || result === "timed_out") {
    return {
      attempt: {
        model,
        latencyMs,
        usage: null,
        timedOut: result === "timed_out",
      },
      reply: null,
    };
  }
  const attempt = {
    model,
    latencyMs,
    usage: readUsage(result.body),
    timedOut: false,
  };
  if (!result.ok) return { attempt, reply: null };
  // A 200 whose body carries no message text is treated as invalid output.
  return { attempt, reply: readReply(result.body) ?? "" };
}

/** A call's answer: whether its status was a success, and its body, null when not JSON. */
type Read = { readonly ok: boolean; readonly body: unknown };

function readReply(body: unknown): string | null {
  if (!isRecord(body) || !Array.isArray(body.choices)) return null;
  const choice: unknown = body.choices[0];
  if (!isRecord(choice) || !isRecord(choice.message)) return null;
  return typeof choice.message.content === "string"
    ? choice.message.content
    : null;
}

function readUsage(body: unknown): Usage | null {
  if (!isRecord(body) || !isRecord(body.usage)) return null;
  const { prompt_tokens, completion_tokens, cost, cost_details } = body.usage;
  if (
    typeof prompt_tokens !== "number" || typeof completion_tokens !== "number"
  ) return null;
  // A call billed through the owner's own provider key (BYOK) reports the provider's price here,
  // and only OpenRouter's own fee in `cost`.
  const upstream = isRecord(cost_details)
    ? cost_details.upstream_inference_cost
    : undefined;
  const parts = [cost, upstream].filter((part) => typeof part === "number");
  return {
    promptTokens: prompt_tokens,
    completionTokens: completion_tokens,
    costUsd: parts.length === 0
      ? null
      : parts.reduce((total, part) => total + part, 0),
  };
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}
