/** The candidate cards a model returns, their JSON schema, and the parser that proves them. */

export const MAX_CARDS = 100;
export const MAX_FIELD_CHARS = 500;
export const MAX_EXAMPLES = 5;

/**
 * One candidate card, each field plain, trimmed, non-empty text as the page prints it.
 * `partOfSpeech` and `examples` are absent when the page prints none; `back` is composed
 * from the others by `composeBack`, for apps that read only `front` and `back`.
 */
export type Card = {
  readonly front: string;
  readonly back: string;
  readonly meaning: string;
  readonly partOfSpeech?: string;
  readonly examples?: readonly string[];
};

const field = {
  type: "string",
  minLength: 1,
  maxLength: MAX_FIELD_CHARS,
} as const;

/**
 * The structured-output schema sent to the model; `parseCards` enforces the same limits.
 * Strict structured outputs require every key, so an absent part of speech is `null` and
 * absent examples are an empty list.
 */
export const cardsSchema = {
  type: "object",
  properties: {
    cards: {
      type: "array",
      maxItems: MAX_CARDS,
      items: {
        type: "object",
        properties: {
          front: field,
          meaning: field,
          partOfSpeech: { ...field, type: ["string", "null"] },
          examples: { type: "array", maxItems: MAX_EXAMPLES, items: field },
        },
        required: ["front", "meaning", "partOfSpeech", "examples"],
        additionalProperties: false,
      },
    },
  },
  required: ["cards"],
  additionalProperties: false,
} as const;

/** The default answer: the part of speech and a space before the meaning, when there is one. */
export function composeBack(meaning: string, partOfSpeech?: string): string {
  return partOfSpeech === undefined ? meaning : `${partOfSpeech} ${meaning}`;
}

/**
 * Parses a model's reply into cards, or returns null when it is not JSON matching
 * `cardsSchema` once each field is trimmed. Lengths count code points, as JSON Schema does.
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
    const card = parseCard(item);
    if (card === null) return null;
    cards.push(card);
  }
  return cards;
}

function parseCard(item: unknown): Card | null {
  if (
    !isRecord(item) ||
    !hasOnlyKeys(item, ["front", "meaning", "partOfSpeech", "examples"])
  ) return null;
  const front = text(item.front);
  const meaning = text(item.meaning);
  const partOfSpeech = item.partOfSpeech === null
    ? undefined
    : text(item.partOfSpeech);
  if (
    front === null || meaning === null || partOfSpeech === null ||
    !Array.isArray(item.examples) || item.examples.length > MAX_EXAMPLES
  ) return null;
  const examples: string[] = [];
  for (const example of item.examples) {
    const parsed = text(example);
    if (parsed === null) return null;
    examples.push(parsed);
  }
  return {
    front,
    back: composeBack(meaning, partOfSpeech),
    meaning,
    ...(partOfSpeech === undefined ? {} : { partOfSpeech }),
    ...(examples.length === 0 ? {} : { examples }),
  };
}

function text(value: unknown): string | null {
  if (typeof value !== "string") return null;
  const trimmed = value.trim();
  const length = [...trimmed].length;
  return length >= 1 && length <= MAX_FIELD_CHARS ? trimmed : null;
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
