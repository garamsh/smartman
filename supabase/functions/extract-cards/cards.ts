/** The candidate cards a model returns, their JSON schema, and the parser that proves them. */

export const MAX_CARDS = 100;
export const MAX_FIELD_CHARS = 500;
export const MAX_ANSWER_CHARS = 1000;
export const MAX_EXAMPLES = 5;
export const MAX_TOPIC_CHARS = 60;
export const MAX_SENSES = 10;
export const MAX_EXTRAS = 10;

/** The detail steps of a page, from its core ideas (1) to every detail (5). */
export const STEPS = [1, 2, 3, 4, 5] as const;
export type Step = (typeof STEPS)[number];

/** What a card was read from: an entry of a vocabulary page, or a point of notes. */
export const KINDS = ["vocabulary", "note"] as const;
export type CardKind = (typeof KINDS)[number];

/**
 * What a card asks: a named concept, rule or cell and its statement; a line of the page with one
 * blank and what fills it; or a sentence the page prints with a word to judge, and its category.
 */
export const TYPES = ["concept", "cloze", "identify"] as const;
export type CardType = (typeof TYPES)[number];

/** One meaning of a vocabulary entry, with the part-of-speech label the page prints for it. */
export type Sense = { readonly pos: string | null; readonly meaning: string };

/** Anything else the page prints for a vocabulary entry, under the page's own label. */
export type Extra = { readonly label: string; readonly text: string };

/**
 * What every card carries, each text field plain, trimmed and non-empty. `type` is what the card
 * asks; `front` the headword or the name of the concept a note states; `answer` the fullest
 * answer the page supports; `topic` the name of the page section the card comes from. `short`
 * and `step` are for an app that reads them, which offered cards by step on a slider (ADR
 * 0052): the answer, and step 1. `back` is the answer an app that reads only `front` and `back`
 * shows. `examples` are those the page prints, absent when it prints none.
 */
type SharedCard = {
  readonly type: CardType;
  readonly front: string;
  readonly answer: string;
  readonly short: string;
  readonly step: Step;
  readonly topic: string;
  readonly back: string;
  readonly examples?: readonly string[];
};

/**
 * A vocabulary entry: its `senses` in page order, and `extras` and `pronunciation` when the page
 * prints them. `answer`, `meaning`, `partOfSpeech` and `back` are composed from the senses for
 * apps that read them (`composeAnswer`).
 */
export type VocabularyCard = SharedCard & {
  readonly kind: "vocabulary";
  readonly senses: readonly Sense[];
  readonly meaning: string;
  readonly partOfSpeech?: string;
  readonly extras?: readonly Extra[];
  readonly pronunciation?: string;
};

/** A point of notes: its `back` is its `answer`. */
export type NoteCard = SharedCard & { readonly kind: "note" };

export type Card = VocabularyCard | NoteCard;

const field = {
  type: "string",
  minLength: 1,
  maxLength: MAX_FIELD_CHARS,
} as const;
const nullableField = { ...field, type: ["string", "null"] } as const;

/** The keys of a card as the model writes it, in the schema's order. */
const MODEL_KEYS = [
  "kind",
  "type",
  "front",
  "answer",
  "topic",
  "senses",
  "extras",
  "pronunciation",
  "examples",
] as const;

/**
 * The structured-output schema sent to the model; `parseCards` enforces the same limits and,
 * beyond what a schema can say, which fields each kind fills: a vocabulary card has senses and
 * no answer, and a note an answer and no senses, extras or pronunciation. Strict structured
 * outputs require every key, so an absent answer or pronunciation is `null` and absent lists
 * are empty. The model writes no `short`, `step`, `meaning`, `partOfSpeech` or `back`: the
 * parser composes them.
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
          type: { type: "string", enum: [...TYPES] },
          front: field,
          answer: { ...nullableField, maxLength: MAX_ANSWER_CHARS },
          topic: { ...field, maxLength: MAX_TOPIC_CHARS },
          senses: {
            type: "array",
            maxItems: MAX_SENSES,
            items: {
              type: "object",
              properties: { pos: nullableField, meaning: field },
              required: ["pos", "meaning"],
              additionalProperties: false,
            },
          },
          extras: {
            type: "array",
            maxItems: MAX_EXTRAS,
            items: {
              type: "object",
              properties: { label: field, text: field },
              required: ["label", "text"],
              additionalProperties: false,
            },
          },
          pronunciation: nullableField,
          examples: { type: "array", maxItems: MAX_EXAMPLES, items: field },
        },
        required: [...MODEL_KEYS],
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
 * The answer and part of speech an app that predates senses reads: one sense gives its meaning
 * and its label, as before; several give one line per sense, each label before its meaning, and
 * no part of speech, so `back` reads one sense per line.
 */
export function composeAnswer(
  senses: readonly Sense[],
): { answer: string; partOfSpeech?: string } {
  if (senses.length === 1) {
    const [{ pos, meaning }] = senses;
    return pos === null
      ? { answer: meaning }
      : { answer: meaning, partOfSpeech: pos };
  }
  return {
    answer: senses.map(({ pos, meaning }) =>
      composeBack(meaning, pos ?? undefined)
    )
      .join("\n"),
  };
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
  if (!isRecord(item) || !hasOnlyKeys(item, MODEL_KEYS)) return null;
  const kind = KINDS.find((known) => known === item.kind);
  const type = TYPES.find((known) => known === item.type);
  const front = text(item.front, MAX_FIELD_CHARS);
  const answer = nullable(item.answer, MAX_ANSWER_CHARS);
  const topic = text(item.topic, MAX_TOPIC_CHARS);
  const pronunciation = nullable(item.pronunciation, MAX_FIELD_CHARS);
  const senses = list(item.senses, MAX_SENSES, parseSense);
  const extras = list(item.extras, MAX_EXTRAS, parseExtra);
  const examples = list(
    item.examples,
    MAX_EXAMPLES,
    (example) => text(example, MAX_FIELD_CHARS),
  );
  if (
    kind === undefined || type === undefined || front === null ||
    answer === undefined ||
    topic === null || pronunciation === undefined || senses === null ||
    extras === null ||
    examples === null
  ) return null;
  const shared = {
    type,
    front,
    // For an app that reads them: every card at the first step.
    step: STEPS[0],
    topic,
    ...(examples.length === 0 ? {} : { examples }),
  };
  if (kind === "note") {
    // A note states its answer, and carries no senses, extras or pronunciation.
    if (
      answer === null || senses.length > 0 || extras.length > 0 ||
      pronunciation !== null
    ) return null;
    return { ...shared, kind, answer, short: answer, back: answer };
  }
  // A vocabulary entry's answer is composed from its senses.
  if (answer !== null || senses.length === 0) return null;
  const composed = composeAnswer(senses);
  return {
    ...shared,
    kind,
    answer: composed.answer,
    short: composed.answer,
    back: composeBack(composed.answer, composed.partOfSpeech),
    meaning: composed.answer,
    senses,
    ...(composed.partOfSpeech === undefined
      ? {}
      : { partOfSpeech: composed.partOfSpeech }),
    ...(extras.length === 0 ? {} : { extras }),
    ...(pronunciation === null ? {} : { pronunciation }),
  };
}

function parseSense(value: unknown): Sense | null {
  if (!isRecord(value) || !hasOnlyKeys(value, ["pos", "meaning"])) return null;
  const pos = nullable(value.pos, MAX_FIELD_CHARS);
  const meaning = text(value.meaning, MAX_FIELD_CHARS);
  return pos === undefined || meaning === null ? null : { pos, meaning };
}

function parseExtra(value: unknown): Extra | null {
  if (!isRecord(value) || !hasOnlyKeys(value, ["label", "text"])) return null;
  const label = text(value.label, MAX_FIELD_CHARS);
  const extra = text(value.text, MAX_FIELD_CHARS);
  return label === null || extra === null ? null : { label, text: extra };
}

/** Each element of [value] parsed, or null when it is not a list of at most [max] valid ones. */
function list<T>(
  value: unknown,
  max: number,
  parse: (element: unknown) => T | null,
): T[] | null {
  if (!Array.isArray(value) || value.length > max) return null;
  const parsed: T[] = [];
  for (const element of value) {
    const one = parse(element);
    if (one === null) return null;
    parsed.push(one);
  }
  return parsed;
}

function text(value: unknown, max: number): string | null {
  if (typeof value !== "string") return null;
  const trimmed = value.trim();
  const length = [...trimmed].length;
  return length >= 1 && length <= max ? trimmed : null;
}

/** [value] as text, null for JSON null, or undefined when it is neither. */
function nullable(value: unknown, max: number): string | null | undefined {
  if (value === null) return null;
  return text(value, max) ?? undefined;
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
