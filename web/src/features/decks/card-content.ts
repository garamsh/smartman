/**
 * One block of a card side, as the phone stores it: a `{type, payload}` object in the side's
 * JSON array (`deck.md`). A text block; a cloze, its text writing each blank as `___` with what
 * fills each, in order; or a table, its column headers, its rows of cells and the cells to
 * recall (ADR 0068); or a vocabulary entry's senses (ADR 0072). A block of another type is
 * shown as a placeholder naming it, so a card a later version wrote is shown, not lost.
 */
export type Content =
  | { kind: "text"; text: string }
  | { kind: "cloze"; text: string; answers: string[] }
  | { kind: "table"; columns: string[]; rows: string[][]; blanks: TableBlank[] }
  | { kind: "senses"; senses: Sense[] }
  | { kind: "unsupported"; type: string };

/** Each part of speech a sense's label may name, with the short form every card shows it as. */
export const partsOfSpeech = {
  noun: "명",
  verb: "동",
  adjective: "형",
  adverb: "부",
  pronoun: "대",
  preposition: "전",
  conjunction: "접",
  interjection: "감",
  determiner: "관",
  numeral: "수",
  particle: "조",
  auxiliary: "조동",
  classifier: "양",
  phrase: "구",
} as const;

export type PartOfSpeech = keyof typeof partsOfSpeech;

/**
 * A label the page prints for a sense, without its brackets: a part of speech, or any other
 * label, such as a semantic class, as printed.
 */
export type SenseLabel =
  | { kind: "part_of_speech"; category: PartOfSpeech; text: string }
  | { kind: "other"; category: null; text: string };

/** One meaning of a vocabulary entry, with the labels the page prints for it, and its examples. */
export type Sense = { labels: SenseLabel[]; meaning: string; examples: string[] };

/** What a card shows inside a label's brackets: a part of speech's short form, else the label as printed. */
export function labelShown(label: SenseLabel): string {
  return label.kind === "part_of_speech" ? partsOfSpeech[label.category] : label.text;
}

/** A sense as one line of text, each label in brackets and one space apart: `[명] 사과`. */
export function senseLine(sense: Sense): string {
  return [...sense.labels.map((label) => `[${labelShown(label)}]`), sense.meaning].join(" ");
}

/** A cell of a table block's rows to recall: its row and column, each counted from 0. */
export type TableBlank = { row: number; column: number };

/** How a cloze's text writes each blank. */
export const clozeBlank = "___";

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null;
}

function isStrings(value: unknown): value is string[] {
  return Array.isArray(value) && value.every((item) => typeof item === "string");
}

/** A cloze of text with one or more blanks, each with a non-empty answer; null otherwise. */
function parseCloze(payload: Record<string, unknown>): Content | null {
  const { text, answers } = payload;
  if (typeof text !== "string" || !isStrings(answers) || answers.length === 0) return null;
  if (answers.some((answer) => answer.trim() === "")) return null;
  if (text.split(clozeBlank).length - 1 !== answers.length) return null;
  return { kind: "cloze", text, answers };
}

/**
 * A table of one or more columns and rows, each row as many cells as there are columns, and one
 * or more distinct blanks inside it, each on a cell that holds text; null otherwise.
 */
function parseTable(payload: Record<string, unknown>): Content | null {
  const { columns, rows, blanks } = payload;
  if (!isStrings(columns) || columns.length === 0) return null;
  if (!Array.isArray(rows) || rows.length === 0) return null;
  if (!rows.every((row) => isStrings(row) && row.length === columns.length)) return null;
  const cells = rows as string[][];
  if (!Array.isArray(blanks) || blanks.length === 0) return null;
  const parsed: TableBlank[] = [];
  for (const blank of blanks as unknown[]) {
    if (!isRecord(blank)) return null;
    const { row, column } = blank;
    if (!Number.isInteger(row) || !Number.isInteger(column)) return null;
    const at = { row: row as number, column: column as number };
    // A cell outside the table reads as "", an empty cell, so this refuses both.
    if ((cells[at.row]?.[at.column] ?? "").trim() === "") return null;
    if (parsed.some((seen) => seen.row === at.row && seen.column === at.column)) return null;
    parsed.push(at);
  }
  return { kind: "table", columns, rows: cells, blanks: parsed };
}

function isPartOfSpeech(value: unknown): value is PartOfSpeech {
  return typeof value === "string" && Object.hasOwn(partsOfSpeech, value);
}

function parseLabel(value: unknown): SenseLabel | null {
  if (!isRecord(value)) return null;
  const { kind, category, text } = value;
  if (typeof text !== "string" || text.trim() === "") return null;
  if (kind === "part_of_speech" && isPartOfSpeech(category)) {
    return { kind, category, text };
  }
  if (kind === "other" && category === null) return { kind, category, text };
  return null;
}

function parseSense(value: unknown): Sense | null {
  if (!isRecord(value)) return null;
  const { labels, meaning, examples } = value;
  if (!Array.isArray(labels) || typeof meaning !== "string" || meaning.trim() === "") return null;
  if (!isStrings(examples)) return null;
  const parsed = labels.map(parseLabel);
  if (parsed.some((label) => label === null)) return null;
  return { labels: parsed as SenseLabel[], meaning, examples };
}

/** One or more senses, each `{labels, meaning, examples}` as the phone writes it; null otherwise. */
function parseSenses(payload: Record<string, unknown>): Content | null {
  const { senses } = payload;
  if (!Array.isArray(senses) || senses.length === 0) return null;
  const parsed = senses.map(parseSense);
  if (parsed.some((sense) => sense === null)) return null;
  return { kind: "senses", senses: parsed as Sense[] };
}

/**
 * The blocks of a stored card side, or null when [value] is not an array of blocks each with
 * a string `type`, and a payload of its type's shape for a text, cloze, table or senses block.
 */
export function parseContent(value: unknown): Content[] | null {
  if (!Array.isArray(value)) return null;
  const blocks: Content[] = [];
  for (const block of value as unknown[]) {
    if (!isRecord(block)) return null;
    const type = "type" in block ? block.type : null;
    const payload = "payload" in block ? block.payload : null;
    if (typeof type !== "string") return null;
    if (type !== "text" && type !== "cloze" && type !== "table" && type !== "senses") {
      blocks.push({ kind: "unsupported", type });
      continue;
    }
    if (!isRecord(payload)) return null;
    const parsed =
      type === "text"
        ? typeof payload.text === "string"
          ? ({ kind: "text", text: payload.text } as const)
          : null
        : type === "cloze"
          ? parseCloze(payload)
          : type === "table"
            ? parseTable(payload)
            : parseSenses(payload);
    if (!parsed) return null;
    blocks.push(parsed);
  }
  return blocks;
}

/** Whether a card with [front] is drawn whole rather than split: whether it holds a cloze or a table. */
export function isWholeCard(front: Content[]): boolean {
  return front.some((block) => block.kind === "cloze" || block.kind === "table");
}

/** Whether a table block's cell at [row] and [column] is one to recall. */
export function isBlank(blanks: TableBlank[], row: number, column: number): boolean {
  return blanks.some((blank) => blank.row === row && blank.column === column);
}

/** A cloze's text with each blank as [fill] gives it, in order. */
function fillCloze(text: string, answers: string[], fill: (answer: string) => string): string {
  return text
    .split(clozeBlank)
    .map((part, index) => part + (index < answers.length ? fill(answers[index] ?? "") : ""))
    .join("");
}

/**
 * The one line of text a card side shows, its blocks joined by spaces, as on the phone: a cloze
 * or a table with its blanks filled.
 */
export function describeContent(blocks: Content[]): string {
  return blocks
    .map((block) => {
      switch (block.kind) {
        case "text":
          return block.text;
        case "cloze":
          return fillCloze(block.text, block.answers, (answer) => answer);
        case "table":
          return [block.columns, ...block.rows].map((cells) => cells.join(" | ")).join("\n");
        case "senses":
          return block.senses.map(senseLine).join("\n");
        case "unsupported":
          return `[이 버전에서 표시할 수 없는 내용: ${block.type}]`;
      }
    })
    .join(" ");
}

/**
 * A card side as a screen reader reads it, as on the phone: each blank as its answer only when
 * [revealed], else as "빈칸", a table row by row, its cells joined by commas, and the blocks as
 * sentences.
 */
export function spokenContent(blocks: Content[], revealed: boolean): string {
  const blank = (answer: string) => (revealed ? answer : "빈칸");
  return blocks
    .map((block) => {
      switch (block.kind) {
        case "cloze":
          return fillCloze(block.text, block.answers, blank);
        case "table":
          return [
            block.columns.join(", "),
            ...block.rows.map((cells, row) =>
              cells
                .map((cell, column) => (isBlank(block.blanks, row, column) ? blank(cell) : cell))
                .join(", "),
            ),
          ].join(". ");
        default:
          return describeContent([block]);
      }
    })
    .join(". ");
}
