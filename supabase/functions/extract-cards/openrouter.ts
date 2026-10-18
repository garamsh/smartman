/**
 * Extracts cards from an image, or surveys it, through OpenRouter chat completions, retrying
 * once on invalid output.
 */

import { type Card, cardsSchema, parseCards } from "./cards.ts";
import { planPrompt } from "./plan_prompt_v1.ts";
import { SYSTEM_PROMPT, userPrompt } from "./prompt_v3.ts";
import type { Image, LanguageHints, Plan } from "./request.ts";
import { parseSurvey, type Survey, surveySchema } from "./survey.ts";
import { SURVEY_PROMPT } from "./survey_prompt_v1.ts";

export const OPENROUTER_URL = "https://openrouter.ai/api/v1/chat/completions";
// Bounds one call's cost; a reply cut off at it fails the schema and is retried.
export const MAX_OUTPUT_TOKENS = 16384;

/** An OpenRouter model ID, such as `anthropic/claude-haiku-5.5`. */
export type ModelId = string & { readonly __brand: "ModelId" };

export function modelId(value: string): ModelId | null {
  return /^[\w.-]+\/[\w.:-]+$/.test(value) ? value as ModelId : null;
}

/** The first call's model, and the model the one retry on invalid output uses. */
export type Models = { readonly primary: ModelId; readonly retry: ModelId };

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

/** Cards from the image: every card the page holds, or, with a plan, only the ones it asks for. */
export async function extractCards(
  image: Image,
  languages: LanguageHints,
  models: Models,
  deps: ExtractDeps,
  plan: Plan | null = null,
): Promise<Extraction> {
  const text = plan === null
    ? userPrompt(languages)
    : `${userPrompt(languages)}\n\n${planPrompt(plan)}`;
  const task = {
    system: SYSTEM_PROMPT,
    text,
    name: "cards",
    schema: cardsSchema,
  };
  const result = await attempt(task, parseCards, image, models, deps);
  if (result.kind !== "parsed") return result;
  return result.value.length === 0
    ? { kind: "no_cards", attempts: result.attempts }
    : { kind: "cards", cards: result.value, attempts: result.attempts };
}

export type SurveyResult =
  | {
    readonly kind: "survey";
    readonly survey: Survey;
    readonly attempts: readonly Attempt[];
  }
  | { readonly kind: "no_cards"; readonly attempts: readonly Attempt[] }
  | { readonly kind: "invalid_output"; readonly attempts: readonly Attempt[] }
  | { readonly kind: "model_error"; readonly attempts: readonly Attempt[] };

/** The page described and its groups named, before any card; no group is `no_cards`. */
export async function surveyPage(
  image: Image,
  languages: LanguageHints,
  models: Models,
  deps: ExtractDeps,
): Promise<SurveyResult> {
  const task = {
    system: SURVEY_PROMPT,
    text: userPrompt(languages),
    name: "survey",
    schema: surveySchema,
  };
  const result = await attempt(task, parseSurvey, image, models, deps);
  if (result.kind !== "parsed") return result;
  return result.value.groups.length === 0
    ? { kind: "no_cards", attempts: result.attempts }
    : { kind: "survey", survey: result.value, attempts: result.attempts };
}

/** What one call asks: its system prompt, its user text beside the image, and its reply schema. */
type Task = {
  readonly system: string;
  readonly text: string;
  readonly name: string;
  readonly schema: unknown;
};

type Attempted<T> =
  | { readonly kind: "parsed"; readonly value: T; readonly attempts: Attempt[] }
  | { readonly kind: "invalid_output"; readonly attempts: Attempt[] }
  | { readonly kind: "model_error"; readonly attempts: Attempt[] };

/** Calls the primary model, and the retry model once when the reply does not parse. */
async function attempt<T>(
  task: Task,
  parse: (reply: string) => T | null,
  image: Image,
  models: Models,
  deps: ExtractDeps,
): Promise<Attempted<T>> {
  const attempts: Attempt[] = [];
  for (const model of [models.primary, models.retry]) {
    const call = await callModel(model, task, image, deps);
    attempts.push(call.attempt);
    if (call.reply === null) return { kind: "model_error", attempts };
    const value = parse(call.reply);
    if (value !== null) return { kind: "parsed", value, attempts };
  }
  return { kind: "invalid_output", attempts };
}

type Call = { readonly attempt: Attempt; readonly reply: string | null };

/** Sends one request; `reply` is the message text, or null when the call itself failed. */
async function callModel(
  model: ModelId,
  task: Task,
  image: Image,
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
          { role: "system", content: task.system },
          {
            role: "user",
            content: [
              { type: "text", text: task.text },
              {
                type: "image_url",
                image_url: { url: `data:${image.type};base64,${image.base64}` },
              },
            ],
          },
        ],
        response_format: {
          type: "json_schema",
          json_schema: { name: task.name, strict: true, schema: task.schema },
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
  // A 200 whose body carries no message text is treated as invalid output, so it is retried.
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
