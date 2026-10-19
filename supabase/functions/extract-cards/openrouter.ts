/** Extracts cards from an image through one OpenRouter chat completion. */

import { type Card, cardsSchema, parseCards } from "./cards.ts";
import { SYSTEM_PROMPT, userPrompt } from "./prompt_v7.ts";
import type { Image, LanguageHints } from "./request.ts";

export const OPENROUTER_URL = "https://openrouter.ai/api/v1/chat/completions";
// Bounds one call's cost; a reply cut off at it fails the schema.
export const MAX_OUTPUT_TOKENS = 16384;

/** An OpenRouter model ID, such as `anthropic/claude-haiku-5.5`. */
export type ModelId = string & { readonly __brand: "ModelId" };

export function modelId(value: string): ModelId | null {
  return /^[\w.-]+\/[\w.:-]+$/.test(value) ? value as ModelId : null;
}

/** What OpenRouter reported for one call; `costUsd` is null when it reported no cost. */
export type Usage = {
  readonly promptTokens: number;
  readonly completionTokens: number;
  readonly costUsd: number | null;
};

/** One model call: the model, how long it took, and its usage when the reply carried one. */
export type Attempt = {
  readonly model: ModelId;
  readonly latencyMs: number;
  readonly usage: Usage | null;
};

export type Extraction =
  | {
    readonly kind: "cards";
    readonly cards: readonly Card[];
    readonly attempts: readonly Attempt[];
  }
  | { readonly kind: "no_cards"; readonly attempts: readonly Attempt[] }
  | { readonly kind: "invalid_output"; readonly attempts: readonly Attempt[] }
  | { readonly kind: "model_error"; readonly attempts: readonly Attempt[] };

export type ExtractDeps = {
  readonly apiKey: string;
  readonly fetch: typeof fetch;
  /** Milliseconds from a monotonic clock. */
  readonly now: () => number;
};

/** One call to [model]; output that is not the schema's is `invalid_output`, with no second call. */
export async function extractCards(
  image: Image,
  languages: LanguageHints,
  model: ModelId,
  deps: ExtractDeps,
): Promise<Extraction> {
  const call = await callModel(model, image, languages, deps);
  const attempts = [call.attempt];
  if (call.reply === null) return { kind: "model_error", attempts };
  const cards = parseCards(call.reply);
  if (cards === null) return { kind: "invalid_output", attempts };
  return cards.length === 0
    ? { kind: "no_cards", attempts }
    : { kind: "cards", cards, attempts };
}

type Call = { readonly attempt: Attempt; readonly reply: string | null };

/** Sends one request; `reply` is the message text, or null when the call itself failed. */
async function callModel(
  model: ModelId,
  image: Image,
  languages: LanguageHints,
  deps: ExtractDeps,
): Promise<Call> {
  const started = deps.now();
  let response: Response;
  try {
    response = await deps.fetch(OPENROUTER_URL, {
      method: "POST",
      headers: {
        "Authorization": `Bearer ${deps.apiKey}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({
        model,
        messages: [
          { role: "system", content: SYSTEM_PROMPT },
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
  } catch {
    return {
      attempt: { model, latencyMs: deps.now() - started, usage: null },
      reply: null,
    };
  }
  const body: unknown = await response.json().catch(() => null);
  const attempt = {
    model,
    latencyMs: deps.now() - started,
    usage: readUsage(body),
  };
  if (!response.ok) return { attempt, reply: null };
  // A 200 whose body carries no message text is treated as invalid output.
  return { attempt, reply: readReply(body) ?? "" };
}

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
  const { prompt_tokens, completion_tokens, cost } = body.usage;
  if (
    typeof prompt_tokens !== "number" || typeof completion_tokens !== "number"
  ) return null;
  return {
    promptTokens: prompt_tokens,
    completionTokens: completion_tokens,
    costUsd: typeof cost === "number" ? cost : null,
  };
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}
