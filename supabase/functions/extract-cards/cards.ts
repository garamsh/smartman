/** The candidate cards a model returns, their JSON schema, and the parser that proves them. */

export const MAX_CARDS = 100;
export const MAX_FIELD_CHARS = 500;
export const MAX_ANSWER_CHARS = 1000;
export const MAX_EXAMPLES = 5;
export const MAX_TOPIC_CHARS = 60;
export const MAX_SENSES = 10;
export const MAX_SENSE_LABELS = 5;
export const MAX_EXTRAS = 10;
export const MAX_TABLE_COLUMNS = 8;
export const MAX_TABLE_ROWS = 20;
export const MAX_CLOZE_BLANKS = 10;

/** The detail steps of a page, from its core ideas (1) to every detail (5). */
export const STEPS = [1, 2, 3, 4, 5] as const;
export type Step = (typeof STEPS)[number];

/** What a card was read from: an entry of a vocabulary page, or a point of notes. */
export const KINDS = ["vocabulary", "note"] as const;
export type CardKind = (typeof KINDS)[number];

/**
 * What a card asks: a named concept, rule or exception and its statement; a line of the page with
 * blanks and what fills each; a sentence the page prints with a word to judge, and its category;
 * or a whole table with the cells to recall as blanks.
 */
export const TYPES = ["concept", "cloze", "identify", "table"] as const;
export type CardType = (typeof TYPES)[number];

/** The parts of speech a label may name, a closed list common across languages (ADR 0075). */
export const PARTS_OF_SPEECH = [
  "noun",
  "verb",
  "adjective",
  "adverb",
  "pronoun",
  "preposition",
  "conjunction",
  "interjection",
  "determiner",
  "numeral",
  "particle",
  "auxiliary",
  "classifier",
  "phrase",
] as const;
export type PartOfSpeech = (typeof PARTS_OF_SPEECH)[number];

/** What a sense label is: a part of speech on the list, or any other label. */
export const LABEL_KINDS = ["part_of_speech", "other"] as const;

/**
 * A label the page prints for a sense, `text` as printed without its enclosing brackets: a part
 * of speech with its category, or any other label, such as a semantic class, with none.
 */
export type SenseLabel =
  | {
    readonly kind: "part_of_speech";
    readonly category: PartOfSpeech;
    readonly text: string;
  }
  | { readonly kind: "other"; readonly category: null; readonly text: string };

/** One meaning of a vocabulary entry, with the labels and examples the page prints for it. */
export type Sense = {
  readonly labels: readonly SenseLabel[];
  readonly meaning: string;
  readonly examples: readonly string[];
};

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
  readonly type: "concept" | "identify";
  readonly senses: readonly Sense[];
  readonly meaning: string;
  readonly partOfSpeech?: string;
  readonly extras?: readonly Extra[];
  readonly pronunciation?: string;
};

/** A cell of a table card's `rows` to recall: its row and column, each counted from 0. */
export type TableBlank = { readonly row: number; readonly column: number };

/**
 * A table card's table as the page prints it: its column headers, its rows of cells, each row as
 * many as there are columns, and the cells to recall. A header or cell the page leaves empty is
 * "", and a blank is never an empty cell.
 */
export type Table = {
  readonly columns: readonly string[];
  readonly rows: readonly (readonly string[])[];
  readonly blanks: readonly TableBlank[];
};

/** A cloze card's blanks: what fills each "___" of its front, in order. */
export type Cloze = { readonly answers: readonly string[] };

type NoteFields = SharedCard & { readonly kind: "note" };

/**
 * A point of notes: its `back` is its `answer`. A cloze card carries its `cloze` and a table card
 * its `table`, and each one's `answer` is composed from them for apps that read only `front`,
 * `answer` and `back` (`composeClozeAnswer`, `composeTableAnswer`).
 */
export type NoteCard =
  | (NoteFields & { readonly type: "concept" | "identify" })
  | (NoteFields & { readonly type: "cloze"; readonly cloze: Cloze })
  | (NoteFields & { readonly type: "table"; readonly table: Table });

export type Card = VocabularyCard | NoteCard;

const field = {
  type: "string",
  minLength: 1,
  maxLength: MAX_FIELD_CHARS,
} as const;
const nullableField = { ...field, type: ["string", "null"] } as const;
/** A table's header or cell, which may be empty where the page leaves it so. */
const cell = { type: "string", maxLength: MAX_FIELD_CHARS } as const;

/** How a cloze card's front writes each blank. */
export const CLOZE_BLANK = "___";

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
  "table",
  "cloze",
] as const;

/**
 * The structured-output schema sent to the model; `parseCards` enforces the same limits and,
 * beyond what a schema can say, which fields each kind fills: a vocabulary card has senses and
 * no answer, and a note an answer and no senses, extras or pronunciation; a table card its
 * `table`, a cloze card its `cloze`, and neither an answer. Strict structured outputs require every
 * key, so an absent answer, pronunciation, table or cloze is `null` and absent lists are empty.
 * Which cells a table holds, and where its blanks are, the parser checks. The model writes no `short`, `step`, `meaning`, `partOfSpeech` or `back`: the
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
              properties: {
                labels: {
                  type: "array",
                  maxItems: MAX_SENSE_LABELS,
                  items: {
                    type: "object",
                    properties: {
                      kind: { type: "string", enum: [...LABEL_KINDS] },
                      category: {
                        anyOf: [
                          { type: "string", enum: [...PARTS_OF_SPEECH] },
                          { type: "null" },
                        ],
                      },
                      text: field,
                    },
                    required: ["kind", "category", "text"],
                    additionalProperties: false,
                  },
                },
                meaning: field,
                examples: {
                  type: "array",
                  maxItems: MAX_EXAMPLES,
                  items: field,
                },
              },
              required: ["labels", "meaning", "examples"],
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
          table: {
            anyOf: [{
              type: "object",
              properties: {
                columns: {
                  type: "array",
                  maxItems: MAX_TABLE_COLUMNS,
                  items: cell,
                },
                rows: {
                  type: "array",
                  maxItems: MAX_TABLE_ROWS,
                  items: {
                    type: "array",
                    maxItems: MAX_TABLE_COLUMNS,
                    items: cell,
                  },
                },
                blanks: {
                  type: "array",
                  maxItems: MAX_TABLE_COLUMNS * MAX_TABLE_ROWS,
                  items: {
                    type: "object",
                    properties: {
                      row: { type: "integer" },
                      column: { type: "integer" },
                    },
                    required: ["row", "column"],
                    additionalProperties: false,
                  },
                },
              },
              required: ["columns", "rows", "blanks"],
              additionalProperties: false,
            }, { type: "null" }],
          },
          cloze: {
            anyOf: [{
              type: "object",
              properties: {
                answers: {
                  type: "array",
                  maxItems: MAX_CLOZE_BLANKS,
                  items: field,
                },
              },
              required: ["answers"],
              additionalProperties: false,
            }, { type: "null" }],
          },
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

/** A sense's labels as printed, each in brackets, or undefined when it has none: `[명] [사물]`. */
function composeLabels(sense: Sense): string | undefined {
  return sense.labels.length === 0
    ? undefined
    : sense.labels.map((label) => `[${label.text}]`).join(" ");
}

/**
 * The answer and part of speech an app that predates senses reads: one sense gives its meaning
 * and its labels, as before; several give one line per sense, its labels before its meaning, and
 * no part of speech, so `back` reads one sense per line.
 */
export function composeAnswer(
  senses: readonly Sense[],
): { answer: string; partOfSpeech?: string } {
  if (senses.length === 1) {
    const [sense] = senses;
    const labels = composeLabels(sense);
    return labels === undefined
      ? { answer: sense.meaning }
      : { answer: sense.meaning, partOfSpeech: labels };
  }
  return {
    answer: senses.map((sense) =>
      composeBack(sense.meaning, composeLabels(sense))
    )
      .join("\n"),
  };
}

/**
 * A cloze card's answer for an app that reads only `front`, `answer` and `back`: what fills each
 * blank, one line per blank in the front's order.
 */
export function composeClozeAnswer(cloze: Cloze): string {
  return cloze.answers.join("\n");
}

/**
 * A table card's answer for an app that reads only `front`, `answer` and `back`: the table as
 * plain text, its column headers on the first line and then one line per row, cells joined by
 * " | ".
 */
export function composeTableAnswer(table: Table): string {
  return [table.columns, ...table.rows].map((cells) => cells.join(" | "))
    .join("\n");
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
  const table = item.table === null ? null : parseTable(item.table);
  const cloze = item.cloze === null ? null : parseCloze(item.cloze);
  if (
    kind === undefined || type === undefined || front === null ||
    answer === undefined ||
    topic === null || pronunciation === undefined || senses === null ||
    extras === null ||
    examples === null || table === undefined || cloze === undefined
  ) return null;
  const shared = {
    front,
    // For an app that reads them: every card at the first step.
    step: STEPS[0],
    topic,
    ...(examples.length === 0 ? {} : { examples }),
  };
  if (kind === "note") {
    // A note carries no senses, extras or pronunciation.
    if (senses.length > 0 || extras.length > 0 || pronunciation !== null) {
      return null;
    }
    if (type === "table") {
      // A table card's answer is its table, composed.
      if (table === null || cloze !== null || answer !== null) return null;
      const composed = composeTableAnswer(table);
      return {
        ...shared,
        kind,
        type,
        answer: composed,
        short: composed,
        back: composed,
        table,
      };
    }
    if (type === "cloze") {
      // A cloze card's answer is what fills its blanks, one for each "___" of its front.
      if (
        cloze === null || table !== null || answer !== null ||
        front.split(CLOZE_BLANK).length - 1 !== cloze.answers.length
      ) return null;
      const composed = composeClozeAnswer(cloze);
      return {
        ...shared,
        kind,
        type,
        answer: composed,
        short: composed,
        back: composed,
        cloze,
      };
    }
    if (answer === null || table !== null || cloze !== null) return null;
    return { ...shared, kind, type, answer, short: answer, back: answer };
  }
  // A vocabulary entry's answer is composed from its senses; it is never a table or a cloze.
  if (
    answer !== null || senses.length === 0 || table !== null ||
    cloze !== null || type === "table" || type === "cloze"
  ) return null;
  const composed = composeAnswer(senses);
  return {
    ...shared,
    kind,
    type,
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

/**
 * A table as the page prints it, or undefined when it is not one: 1 to 8 columns, 1 to 20 rows of
 * exactly that many cells each, and 1 or more distinct blanks, each a cell inside the table that
 * holds text.
 */
function parseTable(value: unknown): Table | undefined {
  if (!isRecord(value) || !hasOnlyKeys(value, ["columns", "rows", "blanks"])) {
    return undefined;
  }
  const columns = list(value.columns, MAX_TABLE_COLUMNS, cellText);
  const rows = list(
    value.rows,
    MAX_TABLE_ROWS,
    (row) => list(row, MAX_TABLE_COLUMNS, cellText),
  );
  const blanks = list(
    value.blanks,
    MAX_TABLE_COLUMNS * MAX_TABLE_ROWS,
    parseTableBlank,
  );
  if (
    columns === null || columns.length === 0 || rows === null ||
    rows.length === 0 || blanks === null || blanks.length === 0
  ) return undefined;
  if (rows.some((row) => row.length !== columns.length)) return undefined;
  const seen = new Set<string>();
  for (const { row, column } of blanks) {
    const at = `${row},${column}`;
    if (
      row >= rows.length || column >= columns.length || seen.has(at) ||
      rows[row][column] === ""
    ) return undefined;
    seen.add(at);
  }
  return { columns, rows, blanks };
}

function parseTableBlank(value: unknown): TableBlank | null {
  if (!isRecord(value) || !hasOnlyKeys(value, ["row", "column"])) return null;
  const { row, column } = value;
  return Number.isInteger(row) && Number.isInteger(column) &&
      (row as number) >= 0 && (column as number) >= 0
    ? { row: row as number, column: column as number }
    : null;
}

/** A cloze's 1 to 10 answers, or undefined when it is not one. */
function parseCloze(value: unknown): Cloze | undefined {
  if (!isRecord(value) || !hasOnlyKeys(value, ["answers"])) return undefined;
  const answers = list(
    value.answers,
    MAX_CLOZE_BLANKS,
    (answer) => text(answer, MAX_FIELD_CHARS),
  );
  return answers === null || answers.length === 0 ? undefined : { answers };
}

/**
 * A sense of `{labels, meaning, examples}`, or null when it is not one: a label's `kind` unknown,
 * a part of speech without a category on the list, another label with a category, or a label,
 * meaning or example empty or over its limit. The eval reads its ground truth through it too.
 */
export function parseSense(value: unknown): Sense | null {
  if (
    !isRecord(value) || !hasOnlyKeys(value, ["labels", "meaning", "examples"])
  ) return null;
  const labels = list(value.labels, MAX_SENSE_LABELS, parseLabel);
  const meaning = text(value.meaning, MAX_FIELD_CHARS);
  const examples = list(
    value.examples,
    MAX_EXAMPLES,
    (example) => text(example, MAX_FIELD_CHARS),
  );
  return labels === null || meaning === null || examples === null
    ? null
    : { labels, meaning, examples };
}

/** The bracket pairs a page may enclose a label in, which its `text` leaves out. */
const LABEL_BRACKETS = [
  "[]",
  "()",
  "<>",
  "「」",
  "『』",
  "〈〉",
  "《》",
  "【】",
  "〔〕",
];

function parseLabel(value: unknown): SenseLabel | null {
  if (!isRecord(value) || !hasOnlyKeys(value, ["kind", "category", "text"])) {
    return null;
  }
  const printed = text(value.text, MAX_FIELD_CHARS);
  if (printed === null) return null;
  // A label written with its brackets keeps only what they enclose.
  const brackets = LABEL_BRACKETS.find(([open, close]) =>
    printed.startsWith(open) && printed.endsWith(close)
  );
  const labelText = brackets === undefined
    ? printed
    : text(printed.slice(1, -1), MAX_FIELD_CHARS);
  if (labelText === null) return null;
  if (value.kind === "other" && value.category === null) {
    return { kind: "other", category: null, text: labelText };
  }
  const category = PARTS_OF_SPEECH.find((known) => known === value.category);
  return value.kind === "part_of_speech" && category !== undefined
    ? { kind: "part_of_speech", category, text: labelText }
    : null;
}

export function parseExtra(value: unknown): Extra | null {
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

/** A table's header or cell trimmed, empty where the page leaves it so, or null when not text. */
function cellText(value: unknown): string | null {
  if (typeof value !== "string") return null;
  const trimmed = value.trim();
  return [...trimmed].length <= MAX_FIELD_CHARS ? trimmed : null;
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
