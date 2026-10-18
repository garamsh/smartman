/**
 * The outline call of the eval's outline-then-fill configurations: one model lists a page's
 * items to memorise, and the function's own extraction, on another model, makes the cards with
 * that list in its user turn. Only the eval runs it; the function is unchanged.
 */

import type {
  Attempt,
  ExtractDeps,
  ModelId,
  Usage,
} from "../../supabase/functions/extract-cards/openrouter.ts";
import { OPENROUTER_URL } from "../../supabase/functions/extract-cards/openrouter.ts";
import type { Image } from "../../supabase/functions/extract-cards/request.ts";

export const OUTLINE_VERSION = "outline v1";
// Bounds the outline call's cost; an outline is a short list, far below a card reply.
export const OUTLINE_MAX_TOKENS = 4096;
export const MAX_OUTLINE_ITEMS = 100;

/** One item a page asks the learner to memorise, as the outline call names it. */
export type OutlineItem = {
  readonly topic: string;
  readonly name: string;
  readonly gist: string;
};

const text = (maxLength: number) =>
  ({ type: "string", minLength: 1, maxLength }) as const;

export const outlineSchema = {
  type: "object",
  properties: {
    items: {
      type: "array",
      maxItems: MAX_OUTLINE_ITEMS,
      items: {
        type: "object",
        properties: { topic: text(60), name: text(200), gist: text(300) },
        required: ["topic", "name", "gist"],
        additionalProperties: false,
      },
    },
  },
  required: ["items"],
  additionalProperties: false,
} as const;

export const OUTLINE_PROMPT =
  `You read one photo of a study page and list what a learner must memorise from it, before anyone writes flashcards.

List, in the order of the page, every definition, every rule, every exception and every line the writer marked as important, such as with a star, a circle, an underline, "※" or "!", including what the writer added by hand. A list the page teaches as one thing to recall, such as a starred list or the members of a table row, is one item. A worked example, a problem worked through, is not an item.

For each item:
- "topic" is the heading of the page section it sits under, without its numbering, at most 60 characters.
- "name" is the name of the concept, rule or exception, as the page words it.
- "gist" is a few words of what it says, from the page.

Invent nothing the page does not show. Leave out what you cannot read with confidence. Answer with JSON only, matching the given schema.`;

/** The outline call's result: its items, or null when the call failed or its reply was not an outline. */
export type Outline = {
  readonly items: readonly OutlineItem[] | null;
  readonly attempt: Attempt;
};

/** Asks [model] for the outline of [image]. */
export async function outline(
  image: Image,
  model: ModelId,
  deps: ExtractDeps,
): Promise<Outline> {
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
          { role: "system", content: OUTLINE_PROMPT },
          {
            role: "user",
            content: [
              { type: "text", text: "List the items of this page." },
              {
                type: "image_url",
                image_url: { url: `data:${image.type};base64,${image.base64}` },
              },
            ],
          },
        ],
        response_format: {
          type: "json_schema",
          json_schema: { name: "outline", strict: true, schema: outlineSchema },
        },
        provider: { require_parameters: true },
        max_tokens: OUTLINE_MAX_TOKENS,
      }),
    });
  } catch {
    return {
      items: null,
      attempt: { model, latencyMs: deps.now() - started, usage: null },
    };
  }
  const body: unknown = await response.json().catch(() => null);
  const attempt = {
    model,
    latencyMs: deps.now() - started,
    usage: usageOf(body),
  };
  return { items: response.ok ? parseOutline(body) : null, attempt };
}

/**
 * [send] with [items] added to the user turn of each OpenRouter request, as a text part before
 * the image, so the function's own prompt and schema write the cards with the outline in view.
 */
export function withOutline(
  send: typeof fetch,
  items: readonly OutlineItem[],
): typeof fetch {
  const listed = items.map((item) =>
    `- ${item.topic} / ${item.name}: ${item.gist}`
  ).join("\n");
  const part = {
    type: "text",
    text:
      `Another reader listed this page's items to memorise:\n${listed}\nMake a card for each item the photo shows, and for anything the list missed. Take every card's text from the photo, not from the list.`,
  };
  return (input, init) => {
    if (String(input) !== OPENROUTER_URL || typeof init?.body !== "string") {
      return send(input, init);
    }
    const request = JSON.parse(init.body);
    const user = request.messages.find((message: { role: string }) =>
      message.role === "user"
    );
    user.content = [user.content[0], part, ...user.content.slice(1)];
    return send(input, { ...init, body: JSON.stringify(request) });
  };
}

function parseOutline(body: unknown): OutlineItem[] | null {
  if (!isRecord(body) || !Array.isArray(body.choices)) return null;
  const choice: unknown = body.choices[0];
  if (!isRecord(choice) || !isRecord(choice.message)) return null;
  const content = choice.message.content;
  if (typeof content !== "string") return null;
  let value: unknown;
  try {
    value = JSON.parse(content);
  } catch {
    return null;
  }
  if (
    !isRecord(value) || !Array.isArray(value.items) ||
    value.items.length > MAX_OUTLINE_ITEMS
  ) return null;
  const items: OutlineItem[] = [];
  for (const item of value.items) {
    if (
      !isRecord(item) || typeof item.topic !== "string" ||
      typeof item.name !== "string" || typeof item.gist !== "string"
    ) return null;
    items.push({ topic: item.topic, name: item.name, gist: item.gist });
  }
  return items;
}

function usageOf(body: unknown): Usage | null {
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
