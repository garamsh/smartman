/**
 * Stage 2 of the two-stage photo import (#414): one card shape made from one stage-1 section.
 * Each shape's reply is checked against the section it was made from, and turned into the
 * cards and blanks the eval scores.
 */

import {
  type Card,
  cardsSchema,
  CLOZE_BLANK,
  composeTableAnswer,
  MAX_CLOZE_BLANKS,
  MAX_FIELD_CHARS,
  MAX_TABLE_COLUMNS,
  MAX_TABLE_ROWS,
  parseCards,
  type Table,
} from "../../supabase/functions/extract-cards/cards.ts";
import { normalize, type NoteCandidate } from "./metrics.ts";
import {
  type ContentType,
  hasOnlyKeys,
  isRecord,
  type Line,
  linesOf,
  list,
  MAX_CELL_LINES,
  MAX_SECTION_LINES,
  parseSpan,
  type Section,
  type Span,
  spanText,
  TABLE_CONTENT,
  text,
} from "./sections.ts";

export const SHAPES = [
  "table_cells",
  "table_spans",
  "qa",
  "cloze",
  "vocabulary",
] as const;
export type Shape = (typeof SHAPES)[number];

/**
 * The shapes made for a section of [type], its default first: the shape the eval scores
 * coverage, cost and latency on, as the app would make one shape a section.
 */
export function shapesFor(type: ContentType): readonly Shape[] {
  if (type === "vocabulary_list") return ["vocabulary"];
  if (TABLE_CONTENT.includes(type)) {
    return ["table_cells", "table_spans", "qa", "cloze"];
  }
  return ["cloze"];
}

/** A cell of a section's table: its row and its column, each counted from 0. */
export type Cell = { readonly row: number; readonly column: number };

/** A blank inside a line: the stage-1 line's id and the span of its text. */
export type LineSpan = Span & { readonly line_id: string };

export type ClozeItem = {
  readonly line_id: string;
  readonly sentence: string;
  readonly blanks: readonly Span[];
  readonly composed: boolean;
};

export type QaCard = Cell & {
  readonly question: string;
  readonly composed: boolean;
};

/** One shape as stage 2 returns it, checked against its section. */
export type ShapeOutput =
  | { readonly kind: "table_cells"; readonly blanks: readonly Cell[] }
  | { readonly kind: "table_spans"; readonly blanks: readonly LineSpan[] }
  | { readonly kind: "qa"; readonly cards: readonly QaCard[] }
  | { readonly kind: "cloze"; readonly items: readonly ClozeItem[] }
  | { readonly kind: "vocabulary"; readonly cards: readonly Card[] };

const field = {
  type: "string",
  minLength: 1,
  maxLength: MAX_FIELD_CHARS,
} as const;
const cell = {
  row: { type: "integer" },
  column: { type: "integer" },
} as const;
const spanFields = {
  start: { type: "integer" },
  end: { type: "integer" },
} as const;
const MAX_TABLE_CELLS = MAX_TABLE_ROWS * MAX_TABLE_COLUMNS;
const MAX_TABLE_LINES = MAX_TABLE_CELLS * MAX_CELL_LINES;

/** Each shape's reply as strict structured outputs state it, keyed by its `kind`. */
export const shapeSchemas = {
  table_cells: {
    type: "object",
    properties: {
      kind: { type: "string", enum: ["table_cells"] },
      blanks: {
        type: "array",
        maxItems: MAX_TABLE_CELLS,
        items: {
          type: "object",
          properties: cell,
          required: ["row", "column"],
          additionalProperties: false,
        },
      },
    },
    required: ["kind", "blanks"],
    additionalProperties: false,
  },
  table_spans: {
    type: "object",
    properties: {
      kind: { type: "string", enum: ["table_spans"] },
      blanks: {
        type: "array",
        maxItems: MAX_TABLE_LINES,
        items: {
          type: "object",
          properties: { line_id: field, ...spanFields },
          required: ["line_id", "start", "end"],
          additionalProperties: false,
        },
      },
    },
    required: ["kind", "blanks"],
    additionalProperties: false,
  },
  qa: {
    type: "object",
    properties: {
      kind: { type: "string", enum: ["qa"] },
      cards: {
        type: "array",
        maxItems: MAX_TABLE_CELLS,
        items: {
          type: "object",
          properties: {
            ...cell,
            question: field,
            composed: { type: "boolean" },
          },
          required: ["row", "column", "question", "composed"],
          additionalProperties: false,
        },
      },
    },
    required: ["kind", "cards"],
    additionalProperties: false,
  },
  cloze: {
    type: "object",
    properties: {
      kind: { type: "string", enum: ["cloze"] },
      items: {
        type: "array",
        maxItems: MAX_TABLE_LINES,
        items: {
          type: "object",
          properties: {
            line_id: field,
            sentence: field,
            blanks: {
              type: "array",
              maxItems: MAX_CLOZE_BLANKS,
              items: {
                type: "object",
                properties: spanFields,
                required: ["start", "end"],
                additionalProperties: false,
              },
            },
            composed: { type: "boolean" },
          },
          required: ["line_id", "sentence", "blanks", "composed"],
          additionalProperties: false,
        },
      },
    },
    required: ["kind", "items"],
    additionalProperties: false,
  },
  vocabulary: {
    type: "object",
    properties: {
      kind: { type: "string", enum: ["vocabulary"] },
      cards: cardsSchema.properties.cards,
    },
    required: ["kind", "cards"],
    additionalProperties: false,
  },
} as const;

/**
 * The [shape] made from [section], or null when [value] is not that shape's reply of the schema's
 * shape, or breaks what the section allows: a cell outside the table or empty, given twice; a
 * span outside its line or over another; a line of another section, or one left without its
 * sentence; no question for a cell that holds lines; a sentence not composed that is not its
 * line word for word; or a vocabulary card that `parseCards` refuses, or a note.
 */
export function parseShape(
  shape: Shape,
  value: unknown,
  section: Section,
): ShapeOutput | null {
  if (!isRecord(value) || value.kind !== shape) return null;
  switch (shape) {
    case "table_cells":
      return hasOnlyKeys(value, ["kind", "blanks"])
        ? parseTableCells(value.blanks, section)
        : null;
    case "table_spans":
      return hasOnlyKeys(value, ["kind", "blanks"])
        ? parseTableSpans(value.blanks, section)
        : null;
    case "qa":
      return hasOnlyKeys(value, ["kind", "cards"])
        ? parseQa(value.cards, section)
        : null;
    case "cloze":
      return hasOnlyKeys(value, ["kind", "items"])
        ? parseCloze(value.items, section)
        : null;
    case "vocabulary":
      return hasOnlyKeys(value, ["kind", "cards"])
        ? parseVocabulary(value.cards)
        : null;
  }
}

/** The lines of [section]'s table cell at [at], or undefined when there is no such cell. */
function cellLines(section: Section, at: Cell): readonly Line[] | undefined {
  return section.table?.rows[at.row]?.cells[at.column]?.lines;
}

function parseCell(value: unknown, section: Section): Cell | null {
  if (!isRecord(value)) return null;
  const { row, column } = value;
  if (
    typeof row !== "number" || typeof column !== "number" ||
    !Number.isInteger(row) || !Number.isInteger(column)
  ) return null;
  const lines = cellLines(section, { row, column });
  return lines === undefined || lines.length === 0 ? null : { row, column };
}

const cellKey = (at: Cell) => `${at.row},${at.column}`;

function parseTableCells(value: unknown, section: Section): ShapeOutput | null {
  if (section.table === null) return null;
  const blanks = list(
    value,
    MAX_TABLE_CELLS,
    (blank) =>
      isRecord(blank) && hasOnlyKeys(blank, ["row", "column"])
        ? parseCell(blank, section)
        : null,
  );
  if (blanks === null || blanks.length === 0) return null;
  return new Set(blanks.map(cellKey)).size === blanks.length
    ? { kind: "table_cells", blanks }
    : null;
}

function parseTableSpans(value: unknown, section: Section): ShapeOutput | null {
  if (section.table === null) return null;
  const lines = new Map(linesOf(section).map((line) => [line.id, line]));
  const blanks = list(value, MAX_TABLE_LINES, (blank): LineSpan | null => {
    if (!isRecord(blank) || !hasOnlyKeys(blank, ["line_id", "start", "end"])) {
      return null;
    }
    const line = typeof blank.line_id === "string"
      ? lines.get(blank.line_id)
      : undefined;
    const at = line === undefined
      ? null
      : parseSpan(blank, [...line.text].length);
    return line === undefined || at === null
      ? null
      : { line_id: line.id, ...at };
  });
  if (blanks === null || blanks.length === 0) return null;
  for (const id of lines.keys()) {
    if (overlap(blanks.filter((blank) => blank.line_id === id))) return null;
  }
  return { kind: "table_spans", blanks };
}

function parseQa(value: unknown, section: Section): ShapeOutput | null {
  if (section.table === null) return null;
  const cards = list(value, MAX_TABLE_CELLS, (card): QaCard | null => {
    if (
      !isRecord(card) ||
      !hasOnlyKeys(card, ["row", "column", "question", "composed"])
    ) return null;
    const at = parseCell(card, section);
    const question = text(card.question);
    return at === null || question === null ||
        typeof card.composed !== "boolean"
      ? null
      : { ...at, question, composed: card.composed };
  });
  if (cards === null) return null;
  const asked = cards.map(cellKey);
  const filled = section.table.rows.flatMap((row, r) =>
    row.cells.flatMap((cell, c) =>
      cell.lines.length > 0 ? [cellKey({ row: r, column: c })] : []
    )
  );
  // Every asked cell holds lines (`parseCell`), so asking each filled cell once is all of them.
  return new Set(asked).size === asked.length &&
      filled.every((key) => asked.includes(key))
    ? { kind: "qa", cards }
    : null;
}

function parseCloze(value: unknown, section: Section): ShapeOutput | null {
  const lines = new Map(linesOf(section).map((line) => [line.id, line]));
  const items = list(
    value,
    MAX_SECTION_LINES * MAX_CELL_LINES,
    (item): ClozeItem | null => {
      if (
        !isRecord(item) ||
        !hasOnlyKeys(item, ["line_id", "sentence", "blanks", "composed"])
      ) return null;
      const line = typeof item.line_id === "string"
        ? lines.get(item.line_id)
        : undefined;
      const sentence = text(item.sentence);
      if (
        line === undefined || sentence === null ||
        typeof item.composed !== "boolean" ||
        (!item.composed && normalize(sentence) !== normalize(line.text))
      ) return null;
      const length = [...sentence].length;
      const blanks = list(
        item.blanks,
        MAX_CLOZE_BLANKS,
        (blank) =>
          isRecord(blank) && hasOnlyKeys(blank, ["start", "end"])
            ? parseSpan(blank, length)
            : null,
      );
      return blanks === null || blanks.length === 0 || overlap(blanks)
        ? null
        : { line_id: line.id, sentence, blanks, composed: item.composed };
    },
  );
  if (items === null) return null;
  const ids = items.map((item) => item.line_id);
  return new Set(ids).size === ids.length && ids.length === lines.size
    ? { kind: "cloze", items }
    : null;
}

function parseVocabulary(value: unknown): ShapeOutput | null {
  const cards = parseCards(JSON.stringify({ cards: value }));
  return cards === null || cards.length === 0 ||
      cards.some((card) => card.kind !== "vocabulary")
    ? null
    : { kind: "vocabulary", cards };
}

/** Whether any two of [spans] share a character. */
function overlap(spans: readonly Span[]): boolean {
  const sorted = [...spans].sort((a, b) => a.start - b.start);
  return sorted.some((span, i) => i > 0 && span.start < sorted[i - 1].end);
}

/** [section]'s table as a table card holds it: the row headers as its first column. */
function tableOf(section: Section, blanks: readonly Cell[]): Table {
  const table = section.table ?? { columns: [], rows: [] };
  return {
    columns: ["", ...table.columns],
    rows: table.rows.map((row) => [
      row.header,
      ...row.cells.map((cell) =>
        cell.lines.map((line) => line.text).join("\n")
      ),
    ]),
    blanks: blanks.map((at) => ({ row: at.row, column: at.column + 1 })),
  };
}

/** A sentence with each of its blanks written `CLOZE_BLANK`, and what fills each. */
function clozeOf(sentence: string, blanks: readonly Span[]) {
  const chars = [...sentence];
  const sorted = [...blanks].sort((a, b) => a.start - b.start);
  let front = "";
  let at = 0;
  for (const blank of sorted) {
    front += chars.slice(at, blank.start).join("") + CLOZE_BLANK;
    at = blank.end;
  }
  front += chars.slice(at).join("");
  return { front, answers: sorted.map((blank) => spanText(sentence, blank)) };
}

/** The cards [output] makes of [section], as the notes metrics read them. */
export function cardsOf(
  output: ShapeOutput,
  section: Section,
): NoteCandidate[] {
  switch (output.kind) {
    case "table_cells":
    case "table_spans": {
      const cells = output.kind === "table_cells"
        ? output.blanks
        : (section.table?.rows ?? []).flatMap((row, r) =>
          row.cells.flatMap((cell, c) =>
            cell.lines.some((line) =>
                output.blanks.some((blank) => blank.line_id === line.id)
              )
              ? [{ row: r, column: c }]
              : []
          )
        );
      const table = tableOf(section, cells);
      return [{
        type: "table",
        front: section.title,
        answer: composeTableAnswer(table),
        table,
      }];
    }
    case "qa":
      return output.cards.map((card) => ({
        type: "concept",
        front: card.question,
        answer: (cellLines(section, card) ?? []).map((line) => line.text)
          .join("\n"),
      }));
    case "cloze":
      return output.items.map((item) => {
        const { front, answers } = clozeOf(item.sentence, item.blanks);
        return {
          type: "cloze",
          front,
          answer: answers.join("\n"),
          cloze: { answers },
        };
      });
    case "vocabulary":
      return [...output.cards];
  }
}

/** A blank a shape asks inside a line: the stage-1 line's text, and the text blanked. */
export type LineBlank = { readonly line: string; readonly text: string };

/**
 * The blanks [output] asks inside lines: a span table's spans, and each cloze blank with the line
 * its sentence was made from. A whole cell, a question or a vocabulary card asks none.
 */
export function lineBlanksOf(
  output: ShapeOutput,
  section: Section,
): LineBlank[] {
  const lines = new Map(linesOf(section).map((line) => [line.id, line.text]));
  switch (output.kind) {
    case "table_spans":
      return output.blanks.map((blank) => {
        const line = lines.get(blank.line_id) ?? "";
        return { line, text: spanText(line, blank) };
      });
    case "cloze":
      return output.items.flatMap((item) =>
        item.blanks.map((blank) => ({
          line: lines.get(item.line_id) ?? "",
          text: spanText(item.sentence, blank),
        }))
      );
    default:
      return [];
  }
}

/** The questions and sentences [output] marks as composed, worded other than the page. */
export function composedOf(output: ShapeOutput): string[] {
  switch (output.kind) {
    case "qa":
      return output.cards.flatMap((card) =>
        card.composed ? [card.question] : []
      );
    case "cloze":
      return output.items.flatMap((item) =>
        item.composed ? [item.sentence] : []
      );
    default:
      return [];
  }
}
