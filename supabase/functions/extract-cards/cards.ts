/** The candidate cards a model returns, their JSON schema, and the parser that proves them. */

export const MAX_CARDS = 100;
export const MAX_SIDE_CHARS = 500;

/** One candidate card: plain, trimmed, non-empty text on each side. */
export type Card = { readonly front: string; readonly back: string };

/** The structured-output schema sent to the model; `parseCards` enforces the same limits. */
export const cardsSchema = {
  type: "object",
  properties: {
    cards: {
      type: "array",
      maxItems: MAX_CARDS,
      items: {
        type: "object",
        properties: {
          front: { type: "string", minLength: 1, maxLength: MAX_SIDE_CHARS },
          back: { type: "string", minLength: 1, maxLength: MAX_SIDE_CHARS },
        },
        required: ["front", "back"],
        additionalProperties: false,
      },
    },
  },
  required: ["cards"],
  additionalProperties: false,
} as const;

/**
 * Parses a model's reply into cards, or returns null when it is not JSON matching
 * `cardsSchema` once each side is trimmed. Lengths count code points, as JSON Schema does.
 */
export function parseCards(reply: string): Card[] | null {
  let value: unknown;
  try {
    value = JSON.parse(reply);
  } catch {
    return null;
  }
  if (!isRecord(value) || !hasOnlyKeys(value, ["cards"])) return null;
  const items = value.cards;
  if (!Array.isArray(items) || items.length > MAX_CARDS) return null;
  const cards: Card[] = [];
  for (const item of items) {
    if (!isRecord(item) || !hasOnlyKeys(item, ["front", "back"])) return null;
    const front = side(item.front);
    const back = side(item.back);
    if (front === null || back === null) return null;
    cards.push({ front, back });
  }
  return cards;
}

function side(value: unknown): string | null {
  if (typeof value !== "string") return null;
  const text = value.trim();
  const length = [...text].length;
  return length >= 1 && length <= MAX_SIDE_CHARS ? text : null;
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

function hasOnlyKeys(
  record: Record<string, unknown>,
  keys: readonly string[],
): boolean {
  const present = Object.keys(record);
  return present.length === keys.length &&
    keys.every((key) => Object.hasOwn(record, key));
}
