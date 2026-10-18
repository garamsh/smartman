/** The candidate cards a model returns, their JSON schema, and the parser that proves them. */

export const MAX_CARDS = 100;
export const MAX_FIELD_CHARS = 500;
export const MAX_ANSWER_CHARS = 1000;
export const MAX_EXAMPLES = 5;
export const MAX_TOPIC_CHARS = 60;

/** The detail steps of a page, from its core ideas (1) to every detail (5). */
export const STEPS = [1, 2, 3, 4, 5] as const;
export type Step = (typeof STEPS)[number];

/** What a card was read from: an entry of a vocabulary page, or a point of notes. */
export const KINDS = ["vocabulary", "note"] as const;
export type CardKind = (typeof KINDS)[number];

/**
 * One candidate card, each text field plain, trimmed and non-empty. `front` is the headword or
 * the name of the concept a note states; `answer` the fullest answer the page supports; `topic`
 * the name of the page section the card comes from. `short` and `step` are for an app that
 * reads them, which offered cards by step on a slider (ADR 0052): the answer, and step 1. A vocabulary card also carries
 * `meaning` (its answer), and `partOfSpeech` and `examples` when the page prints them; a note
 * card may carry `examples` the page prints. `back` is the answer an app that reads only
 * `front` and `back` shows: a vocabulary card's `composeBack`, or a note card's `answer`.
 */
export type Card = {
  readonly kind: CardKind;
  readonly front: string;
  readonly answer: string;
  readonly short: string;
  readonly step: Step;
  readonly topic: string;
  readonly back: string;
  readonly meaning?: string;
  readonly partOfSpeech?: string;
  readonly examples?: readonly string[];
};

const field = {
  type: "string",
  minLength: 1,
  maxLength: MAX_FIELD_CHARS,
} as const;

/**
 * The structured-output schema sent to the model; `parseCards` enforces the same limits and,
 * beyond what a schema can say, that only a vocabulary card has a part of speech. Strict
 * structured outputs require every key, so an absent part of speech is `null` and absent
 * examples are an empty list. The model writes no `short` or `step`: the parser fills both.
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
          kind: { type: "string", enum: [...KINDS] },
          front: field,
          answer: { ...field, maxLength: MAX_ANSWER_CHARS },
          topic: { ...field, maxLength: MAX_TOPIC_CHARS },
          partOfSpeech: { ...field, type: ["string", "null"] },
          examples: { type: "array", maxItems: MAX_EXAMPLES, items: field },
        },
        required: [
          "kind",
          "front",
          "answer",
          "topic",
          "partOfSpeech",
          "examples",
        ],
        additionalProperties: false,
      },
    },
  },
  required: ["cards"],
  additionalProperties: false,
} as const;

/** A vocabulary card's default answer: the part of speech and a space before the meaning. */
export function composeBack(meaning: string, partOfSpeech?: string): string {
  return partOfSpeech === undefined ? meaning : `${partOfSpeech} ${meaning}`;
}

/**
 * Parses a model's reply into cards, or returns null when it is not JSON matching
 * `cardsSchema` once each field is trimmed, or breaks a rule the schema cannot state. Lengths
 * count code points, as JSON Schema does.
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
    !hasOnlyKeys(item, [
      "kind",
      "front",
      "answer",
      "topic",
      "partOfSpeech",
      "examples",
    ])
  ) return null;
  const kind = KINDS.find((known) => known === item.kind);
  const front = text(item.front, MAX_FIELD_CHARS);
  const answer = text(item.answer, MAX_ANSWER_CHARS);
  const topic = text(item.topic, MAX_TOPIC_CHARS);
  const partOfSpeech = item.partOfSpeech === null
    ? undefined
    : text(item.partOfSpeech, MAX_FIELD_CHARS);
  if (
    kind === undefined || front === null || answer === null ||
    topic === null || partOfSpeech === null ||
    !Array.isArray(item.examples) || item.examples.length > MAX_EXAMPLES
  ) return null;
  // Notes carry no part of speech.
  if (kind === "note" && partOfSpeech !== undefined) return null;
  const examples: string[] = [];
  for (const example of item.examples) {
    const parsed = text(example, MAX_FIELD_CHARS);
    if (parsed === null) return null;
    examples.push(parsed);
  }
  const shared = {
    kind,
    front,
    answer,
    // For an app that reads them: every card at the first step, its answer its short form.
    short: answer,
    step: STEPS[0],
    topic,
    ...(examples.length === 0 ? {} : { examples }),
  };
  return kind === "vocabulary"
    ? {
      ...shared,
      back: composeBack(answer, partOfSpeech),
      meaning: answer,
      ...(partOfSpeech === undefined ? {} : { partOfSpeech }),
    }
    : { ...shared, back: answer };
}

function text(value: unknown, max: number): string | null {
  if (typeof value !== "string") return null;
  const trimmed = value.trim();
  const length = [...trimmed].length;
  return length >= 1 && length <= max ? trimmed : null;
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
