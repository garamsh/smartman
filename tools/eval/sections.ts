/**
 * Stage 1 of the two-stage photo import (#414): a page's sections, each a table of bullet lines
 * or a list of lines, every line with the marks on it. The same shape holds a page's ground
 * truth, whose lines carry the spans a card should blank instead of the model's key terms.
 */

import {
  MAX_FIELD_CHARS,
  MAX_TABLE_COLUMNS,
  MAX_TABLE_ROWS,
} from "../../supabase/functions/extract-cards/cards.ts";

export const CONTENT_TYPES = [
  "vocabulary_list",
  "comparison_table",
  "table",
  "rule_list",
  "process",
  "worked_examples",
  "prose",
] as const;
export type ContentType = (typeof CONTENT_TYPES)[number];

/** The content types whose section holds a table and no lines. */
export const TABLE_CONTENT: readonly ContentType[] = [
  "comparison_table",
  "table",
];

export const MARK_KINDS = ["underline", "circle", "highlight", "star"] as const;
export type MarkKind = (typeof MARK_KINDS)[number];
/** The marks that cover a span of a line, a word to blank; a star marks a line as a whole. */
export const SPAN_MARKS: readonly MarkKind[] = [
  "underline",
  "circle",
  "highlight",
];
export const INKS = ["print", "pen"] as const;
export const KEY_TERM_SOURCES = ["mark", "model"] as const;
/**
 * What a line is to a card: a fact to recall, an example of the fact before it, or a heading that
 * only names what follows.
 */
export const LINE_ROLES = ["fact", "example", "heading"] as const;
export type LineRole = (typeof LINE_ROLES)[number];

export const MAX_SECTIONS = 20;
export const MAX_SECTION_LINES = 60;
export const MAX_CELL_LINES = 10;
export const MAX_LINE_SPANS = 10;

/** A run of a line's characters, counted in code points from 0, `end` exclusive. */
export type Span = { readonly start: number; readonly end: number };
export type Mark = Span & {
  readonly kind: MarkKind;
  readonly ink: (typeof INKS)[number];
};
export type KeyTerm = Span & {
  readonly source: (typeof KEY_TERM_SOURCES)[number];
};

/** A printed line as stage 1 returns it: its key terms, from a mark or the model's choice. */
export type Line = {
  readonly id: string;
  readonly text: string;
  readonly role: LineRole;
  readonly marks: readonly Mark[];
  readonly key_terms: readonly KeyTerm[];
};

/** A line as a ground truth records it: the spans a card should blank. */
export type TruthLine = {
  readonly id: string;
  readonly text: string;
  readonly marks: readonly Mark[];
  readonly blanks: readonly Span[];
};

/** A table whose cells hold lines; `columns` leaves out the column that names the rows. */
export type Table<L> = {
  readonly columns: readonly string[];
  readonly rows: readonly {
    readonly header: string;
    readonly cells: readonly { readonly lines: readonly L[] }[];
  }[];
};

/** A section: a table and no lines when its content is a table, or lines and no table. */
export type Section<L = Line> = {
  readonly title: string;
  readonly language: string;
  readonly content_type: ContentType;
  readonly lines: readonly L[];
  readonly table: Table<L> | null;
};

/** Every line of [section], a table's row by row and cell by cell. */
export function linesOf<L>(section: Section<L>): readonly L[] {
  return section.table === null
    ? section.lines
    : section.table.rows.flatMap((row) =>
      row.cells.flatMap((cell) => cell.lines)
    );
}

/** The text a span of [text] covers. */
export function spanText(text: string, span: Span): string {
  return [...text].slice(span.start, span.end).join("");
}

/**
 * The span of [text] that first holds [covered] at or after code point [from], or null when
 * none does or [covered] is empty.
 */
export function spanOf(text: string, covered: string, from = 0): Span | null {
  const chars = [...text];
  const want = [...covered];
  if (want.length === 0) return null;
  for (let start = from; start + want.length <= chars.length; start += 1) {
    if (want.every((char, i) => chars[start + i] === char)) {
      return { start, end: start + want.length };
    }
  }
  return null;
}

// The schema states no length or count: strict structured outputs do not support those
// constraints, and the parsers below enforce them.
const field = { type: "string" } as const;

/** The row and column stage 1 gives a line outside a table. */
export const NO_CELL = -1;

/**
 * Stage 1's reply, `{kind: "sections", sections}`, as strict structured outputs state it. A table
 * is flat: its columns and row headers as text, and each line names its cell by row and column,
 * which keeps the schema shallow and states a line once. A mark or key term gives the text it
 * covers, which `parseSections` finds in its line.
 */
export const sectionsSchema = {
  type: "object",
  properties: {
    kind: { type: "string", enum: ["sections"] },
    sections: {
      type: "array",
      items: {
        type: "object",
        properties: {
          title: field,
          language: field,
          content_type: { type: "string", enum: [...CONTENT_TYPES] },
          columns: { type: "array", items: field },
          rows: { type: "array", items: field },
          lines: {
            type: "array",
            items: {
              type: "object",
              properties: {
                id: field,
                text: field,
                role: { type: "string", enum: [...LINE_ROLES] },
                row: { type: "integer" },
                column: { type: "integer" },
                marks: {
                  type: "array",
                  items: {
                    type: "object",
                    properties: {
                      text: field,
                      kind: { type: "string", enum: [...MARK_KINDS] },
                      ink: { type: "string", enum: [...INKS] },
                    },
                    required: ["text", "kind", "ink"],
                    additionalProperties: false,
                  },
                },
                key_terms: {
                  type: "array",
                  items: {
                    type: "object",
                    properties: {
                      text: field,
                      source: { type: "string", enum: [...KEY_TERM_SOURCES] },
                    },
                    required: ["text", "source"],
                    additionalProperties: false,
                  },
                },
              },
              required: [
                "id",
                "text",
                "role",
                "row",
                "column",
                "marks",
                "key_terms",
              ],
              additionalProperties: false,
            },
          },
        },
        required: [
          "title",
          "language",
          "content_type",
          "columns",
          "rows",
          "lines",
        ],
        additionalProperties: false,
      },
    },
  },
  required: ["kind", "sections"],
  additionalProperties: false,
} as const;

const FLAT_KEYS = [
  "title",
  "language",
  "content_type",
  "columns",
  "rows",
  "lines",
] as const;

/**
 * Stage 1's sections, or null when [value] is not `{kind: "sections", sections}` of the schema's
 * shape once each text is trimmed, or breaks a rule the schema cannot state: a table section
 * without columns or rows, another section with either or with no line, a table line outside its
 * table, a list line given a cell, a line id given twice on the page, or a mark or key term whose
 * text its line does not hold. A star covers its whole line, whatever text it gives.
 */
export function parseSections(value: unknown): Section[] | null {
  if (!isRecord(value) || !hasOnlyKeys(value, ["kind", "sections"])) {
    return null;
  }
  if (value.kind !== "sections") return null;
  const tree = list(value.sections, MAX_SECTIONS, treeOf);
  return tree === null ? null : parseSectionTree(tree);
}

/** A flat section in the nested shape, or null when a line's cell is not one of its own. */
function treeOf(value: unknown): Record<string, unknown> | null {
  if (
    !isRecord(value) || !hasOnlyKeys(value, FLAT_KEYS) ||
    !Array.isArray(value.columns) || !Array.isArray(value.rows)
  ) return null;
  const { columns, rows, lines, ...rest } = value;
  const placed = list(
    lines,
    MAX_TABLE_ROWS * MAX_TABLE_COLUMNS * MAX_CELL_LINES,
    (line) => {
      if (!isRecord(line)) return null;
      const { row, column, ...flat } = line;
      const printed = spannedOf(flat);
      return typeof row === "number" && typeof column === "number" &&
          printed !== null
        ? { row, column, line: printed }
        : null;
    },
  );
  if (placed === null) return null;
  if (columns.length === 0 && rows.length === 0) {
    return placed.every((one) => one.row === NO_CELL && one.column === NO_CELL)
      ? { ...rest, lines: placed.map((one) => one.line), table: null }
      : null;
  }
  const inside = placed.every((one) =>
    Number.isInteger(one.row) && Number.isInteger(one.column) &&
    one.row >= 0 && one.row < rows.length &&
    one.column >= 0 && one.column < columns.length
  );
  return inside
    ? {
      ...rest,
      lines: [],
      table: {
        columns,
        rows: rows.map((header, r) => ({
          header,
          cells: columns.map((_, c) => ({
            lines: placed.filter((one) => one.row === r && one.column === c)
              .map((one) => one.line),
          })),
        })),
      },
    }
    : null;
}

/**
 * A flat line with each mark and key term turned from the text it covers into that text's first
 * span in the line, a star into the whole line; null when the line does not hold such a text.
 * Everything else about the line is left for `parseLine` to check.
 */
function spannedOf(
  line: Record<string, unknown>,
): Record<string, unknown> | null {
  const printed = text(line.text);
  if (printed === null) return line;
  const spanned = (value: unknown) =>
    list(value, MAX_LINE_SPANS, (item) => {
      if (!isRecord(item) || typeof item.text !== "string") return null;
      const { text: covered, ...rest } = item;
      const at = rest.kind === "star"
        ? { start: 0, end: [...printed].length }
        : spanOf(printed, covered.trim());
      return at === null ? null : { ...at, ...rest };
    });
  const marks = spanned(line.marks);
  const keyTerms = spanned(line.key_terms);
  return marks === null || keyTerms === null
    ? null
    : { ...line, marks, key_terms: keyTerms };
}

/**
 * [section] in the flat shape stage 1 writes, the shape stage 2 is given it in: each mark and key
 * term as the text it covers.
 */
export function flatOf(section: Section): Record<string, unknown> {
  const covered =
    (line: Line) => <T extends Span>({ start, end, ...rest }: T) => ({
      text: spanText(line.text, { start, end }),
      ...rest,
    });
  const flat = (line: Line, row: number, column: number) => ({
    id: line.id,
    text: line.text,
    role: line.role,
    row,
    column,
    marks: line.marks.map(covered(line)),
    key_terms: line.key_terms.map(covered(line)),
  });
  const { table } = section;
  return {
    title: section.title,
    language: section.language,
    content_type: section.content_type,
    columns: table?.columns ?? [],
    rows: table?.rows.map((row) => row.header) ?? [],
    lines: table === null
      ? section.lines.map((line) => flat(line, NO_CELL, NO_CELL))
      : table.rows.flatMap((row, r) =>
        row.cells.flatMap((cell, c) =>
          cell.lines.map((line) => flat(line, r, c))
        )
      ),
  };
}

/**
 * Sections in the nested shape, a table's rows of cells of lines, or null when they break a rule
 * `parseSections` names or a row is not as wide as the columns.
 */
export function parseSectionTree(value: unknown): Section[] | null {
  return parseStructure(value, parseLine);
}

/** A ground truth's `sections`, or null when they are not of the stage-1 shape with blanks. */
export function parseTruthSections(
  value: unknown,
): Section<TruthLine>[] | null {
  return parseStructure(value, parseTruthLine);
}

function parseStructure<L extends { readonly id: string }>(
  value: unknown,
  parseOne: (value: unknown) => L | null,
): Section<L>[] | null {
  if (
    !Array.isArray(value) || value.length === 0 || value.length > MAX_SECTIONS
  ) return null;
  const sections: Section<L>[] = [];
  for (const item of value) {
    const section = parseSection(item, parseOne);
    if (section === null) return null;
    sections.push(section);
  }
  const ids = sections.flatMap((section) =>
    linesOf(section).map((line) => line.id)
  );
  return new Set(ids).size === ids.length ? sections : null;
}

function parseSection<L>(
  value: unknown,
  parseOne: (value: unknown) => L | null,
): Section<L> | null {
  if (
    !isRecord(value) ||
    !hasOnlyKeys(value, ["title", "language", "content_type", "lines", "table"])
  ) return null;
  const title = text(value.title);
  const language = text(value.language);
  const contentType = CONTENT_TYPES.find((known) =>
    known === value.content_type
  );
  const lines = list(value.lines, MAX_SECTION_LINES, parseOne);
  if (
    title === null || language === null ||
    !/^[A-Za-z]{2,3}(-[A-Za-z0-9]{2,8})*$/.test(language) ||
    contentType === undefined || lines === null
  ) return null;
  if (!TABLE_CONTENT.includes(contentType)) {
    return value.table === null && lines.length > 0
      ? { title, language, content_type: contentType, lines, table: null }
      : null;
  }
  const table = parseTable(value.table, parseOne);
  return table === null || lines.length > 0
    ? null
    : { title, language, content_type: contentType, lines, table };
}

function parseTable<L>(
  value: unknown,
  parseOne: (value: unknown) => L | null,
): Table<L> | null {
  if (!isRecord(value) || !hasOnlyKeys(value, ["columns", "rows"])) {
    return null;
  }
  const columns = list(value.columns, MAX_TABLE_COLUMNS, text);
  if (columns === null || columns.length === 0) return null;
  const rows = list(value.rows, MAX_TABLE_ROWS, (row) => {
    if (!isRecord(row) || !hasOnlyKeys(row, ["header", "cells"])) return null;
    const header = text(row.header);
    const cells = list(row.cells, MAX_TABLE_COLUMNS, (cell) => {
      if (!isRecord(cell) || !hasOnlyKeys(cell, ["lines"])) return null;
      const lines = list(cell.lines, MAX_CELL_LINES, parseOne);
      return lines === null ? null : { lines };
    });
    return header === null || cells === null ||
        cells.length !== columns.length
      ? null
      : { header, cells };
  });
  return rows === null || rows.length === 0 ? null : { columns, rows };
}

function parseLine(value: unknown): Line | null {
  if (
    !isRecord(value) ||
    !hasOnlyKeys(value, ["id", "text", "role", "marks", "key_terms"])
  ) return null;
  const id = text(value.id);
  const printed = text(value.text);
  const role = LINE_ROLES.find((known) => known === value.role);
  if (id === null || printed === null || role === undefined) return null;
  const length = [...printed].length;
  const marks = list(
    value.marks,
    MAX_LINE_SPANS,
    (mark) => parseMark(mark, length),
  );
  const keyTerms = list(value.key_terms, MAX_LINE_SPANS, (term) => {
    if (!isRecord(term) || !hasOnlyKeys(term, ["start", "end", "source"])) {
      return null;
    }
    const at = parseSpan(term, length);
    const source = KEY_TERM_SOURCES.find((known) => known === term.source);
    return at === null || source === undefined ? null : { ...at, source };
  });
  return marks === null || keyTerms === null
    ? null
    : { id, text: printed, role, marks, key_terms: keyTerms };
}

function parseTruthLine(value: unknown): TruthLine | null {
  if (
    !isRecord(value) || !hasOnlyKeys(value, ["id", "text", "marks", "blanks"])
  ) return null;
  const id = text(value.id);
  const printed = text(value.text);
  if (id === null || printed === null) return null;
  const length = [...printed].length;
  const marks = list(
    value.marks,
    MAX_LINE_SPANS,
    (mark) => parseMark(mark, length),
  );
  const blanks = list(
    value.blanks,
    MAX_LINE_SPANS,
    (blank) =>
      isRecord(blank) && hasOnlyKeys(blank, ["start", "end"])
        ? parseSpan(blank, length)
        : null,
  );
  return marks === null || blanks === null || blanks.length === 0
    ? null
    : { id, text: printed, marks, blanks };
}

function parseMark(value: unknown, length: number): Mark | null {
  if (
    !isRecord(value) || !hasOnlyKeys(value, ["start", "end", "kind", "ink"])
  ) {
    return null;
  }
  const at = parseSpan(value, length);
  const kind = MARK_KINDS.find((known) => known === value.kind);
  const ink = INKS.find((known) => known === value.ink);
  return at === null || kind === undefined || ink === undefined
    ? null
    : { ...at, kind, ink };
}

/** A span inside a text of [length] code points, or null when it is empty or runs outside. */
export function parseSpan(
  value: Record<string, unknown>,
  length: number,
): Span | null {
  const { start, end } = value;
  return Number.isInteger(start) && Number.isInteger(end) &&
      typeof start === "number" && typeof end === "number" &&
      start >= 0 && start < end && end <= length
    ? { start, end }
    : null;
}

/** Each element of [value] parsed, or null when it is not a list of at most [max] valid ones. */
export function list<T>(
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

/** [value] trimmed, or null when it is not text of 1 to `MAX_FIELD_CHARS` code points. */
export function text(value: unknown): string | null {
  if (typeof value !== "string") return null;
  const trimmed = value.trim();
  const length = [...trimmed].length;
  return length >= 1 && length <= MAX_FIELD_CHARS ? trimmed : null;
}

export function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

/** Whether [value] holds exactly [keys]. */
export function hasOnlyKeys(
  value: Record<string, unknown>,
  keys: readonly string[],
): boolean {
  const present = Object.keys(value);
  return present.length === keys.length &&
    present.every((key) => keys.includes(key));
}
