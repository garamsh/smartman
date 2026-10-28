/**
 * One block of a card side, as the phone stores it: a `{type, v, id, payload}` object in the
 * side's JSON array (`deck.md`), its kind the `type` and its version the `v`, read as 1 when
 * absent (ADR 0106). A text block; a cloze, its text writing each blank as `___` with what fills
 * each, in order; or a table, its column headers, its rows of cells, the cells to recall whole
 * (ADR 0068) and the runs of cells' text to recall (ADR 0110); or a vocabulary entry's senses (ADR 0075); or a photo by its media id, with its
 * intrinsic size and the boxes over it (ADR 0109); or a sound by its media id, with how long it
 * plays in milliseconds (ADR 0112). A block of another type, or of a known
 * type at a version above the one this build reads, is shown as a placeholder naming it, so a
 * card a later version wrote is shown, not lost. Authoring inserts new cards and leaves stored
 * cards unchanged.
 */
export type Content =
  | { kind: "text"; text: string }
  | { kind: "cloze"; text: string; answers: string[] }
  | {
      kind: "table";
      columns: string[];
      rows: string[][];
      blanks: TableBlank[];
      spans: CellSpan[];
    }
  | { kind: "senses"; senses: Sense[] }
  | { kind: "image"; media: string; width: number; height: number; boxes: ImageBox[] }
  | { kind: "audio"; media: string; durationMs: number }
  | { kind: "unsupported"; type: string };

/**
 * A box over a photo, a blank to recall: its left, top, width and height as fractions, from 0
 * to 1, of the stored image's own width and height, never of a screen, so it covers the same
 * part of the photo at every size it is drawn at, and the answer shown in it once revealed, if
 * any (ADR 0109).
 */
export type ImageBox = {
  id: string;
  x: number;
  y: number;
  w: number;
  h: number;
  answer: string | null;
};

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

/** A cell of a table block's rows to recall whole: its row and column, each counted from 0. */
export type TableBlank = { row: number; column: number };

/**
 * A run of a table cell's text to recall: the cell's row and column, each counted from 0, and
 * the run's start and end in the cell's UTF-16 code units, as the phone's `CellSpan` (ADR 0110).
 */
export type CellSpan = { row: number; column: number; start: number; end: number };

/** A part of a table cell's text, and whether it is a blank. */
export type CellRun = { text: string; blank: boolean };

/** How a cloze's text writes each blank. */
export const clozeBlank = "___";

type KnownType = "text" | "cloze" | "table" | "senses" | "image" | "audio";

/**
 * The steps that upgrade each known type's payload, one per version: the first turns a v1
 * payload into a v2 one, and so on, as the app's `blockUpcasters` does. The version a type is
 * read at is one more than its steps: a table at v2, every other type at v1.
 */
/**
 * A v1 table's payload as v2's: its blanks stay whole cells, and it holds no span (ADR 0110).
 * A payload that is not an object is left to fail parsing.
 */
function tableWithSpans(payload: unknown): unknown {
  return isRecord(payload) ? { ...payload, spans: [] } : payload;
}

export const blockUpcasters: Record<KnownType, ((payload: unknown) => unknown)[]> = {
  text: [],
  cloze: [],
  table: [tableWithSpans],
  senses: [],
  image: [],
  audio: [],
};

function isKnownType(type: string): type is KnownType {
  return Object.hasOwn(blockUpcasters, type);
}

/** The version of [type] this build reads, given the [steps] that reach it. */
export function blockVersion(
  type: KnownType,
  steps: Record<KnownType, ((payload: unknown) => unknown)[]> = blockUpcasters,
): number {
  return steps[type].length + 1;
}

/** [payload], stored at [version] of [type], upgraded step by step to the version this build reads. */
export function upcastPayload(
  type: KnownType,
  version: number,
  payload: unknown,
  steps: Record<KnownType, ((payload: unknown) => unknown)[]> = blockUpcasters,
): unknown {
  let upgraded = payload;
  for (const step of steps[type].slice(version - 1)) upgraded = step(upgraded);
  return upgraded;
}

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
 * or more blanks inside it, whole cells and spans together: each whole cell distinct and holding
 * text, and each span a run of a cell's text holding more than whitespace, overlapping no other
 * span and in no whole cell (ADR 0110); null otherwise.
 */
function parseTable(payload: Record<string, unknown>): Content | null {
  const { columns, rows, blanks, spans } = payload;
  if (!isStrings(columns) || columns.length === 0) return null;
  if (!Array.isArray(rows) || rows.length === 0) return null;
  if (!rows.every((row) => isStrings(row) && row.length === columns.length)) return null;
  const cells = rows as string[][];
  if (!Array.isArray(blanks) || !Array.isArray(spans)) return null;
  if (blanks.length === 0 && spans.length === 0) return null;
  const parsed: TableBlank[] = [];
  for (const blank of blanks as unknown[]) {
    if (!isRecord(blank)) return null;
    const { row, column } = blank;
    if (!Number.isInteger(row) || !Number.isInteger(column)) return null;
    const at = { row: row as number, column: column as number };
    // A cell outside the table reads as "", an empty cell, so this refuses both.
    if ((cells[at.row]?.[at.column] ?? "").trim() === "") return null;
    if (isBlank(parsed, at.row, at.column)) return null;
    parsed.push(at);
  }
  const runs: CellSpan[] = [];
  for (const span of spans as unknown[]) {
    if (!isRecord(span)) return null;
    const { row, column, start, end } = span;
    if (![row, column, start, end].every(Number.isInteger)) return null;
    const at = {
      row: row as number,
      column: column as number,
      start: start as number,
      end: end as number,
    };
    // A row or column outside the table, negative ones included, reads as undefined.
    const cell = cells[at.row]?.[at.column];
    if (cell === undefined || isBlank(parsed, at.row, at.column)) return null;
    if (at.start < 0 || at.start >= at.end || at.end > cell.length) return null;
    if (cell.slice(at.start, at.end).trim() === "") return null;
    const overlaps = runs.some(
      (seen) =>
        seen.row === at.row &&
        seen.column === at.column &&
        seen.start < at.end &&
        at.start < seen.end,
    );
    if (overlaps) return null;
    runs.push(at);
  }
  return { kind: "table", columns, rows: cells, blanks: parsed, spans: runs };
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

/** How far past 1 a box's far edge may fall, for a fraction's rounding, as on the phone. */
const boxTolerance = 1e-9;

function isFraction(value: unknown): value is number {
  return typeof value === "number" && Number.isFinite(value);
}

/**
 * A box of a non-empty id, an optional text answer, and a left and top at or above 0 and a
 * width and height above 0 whose far edges fall inside the image; null otherwise.
 */
function parseBox(value: unknown): ImageBox | null {
  if (!isRecord(value)) return null;
  const { id, x, y, w, h } = value;
  const answer = "answer" in value ? value.answer : null;
  if (typeof id !== "string" || id === "") return null;
  if (!isFraction(x) || !isFraction(y) || !isFraction(w) || !isFraction(h)) return null;
  if (x < 0 || y < 0 || w <= 0 || h <= 0) return null;
  if (x + w > 1 + boxTolerance || y + h > 1 + boxTolerance) return null;
  if (answer !== null && typeof answer !== "string") return null;
  return { id, x, y, w, h, answer };
}

/**
 * A photo of a non-empty media id, a positive whole width and height, and boxes, their ids
 * distinct; null otherwise (ADR 0109).
 */
function parseImage(payload: Record<string, unknown>): Content | null {
  const { media, width, height, boxes } = payload;
  if (typeof media !== "string" || media === "") return null;
  if (!Number.isInteger(width) || !Number.isInteger(height)) return null;
  if ((width as number) <= 0 || (height as number) <= 0) return null;
  if (!Array.isArray(boxes)) return null;
  const parsed = (boxes as unknown[]).map(parseBox);
  if (parsed.some((box) => box === null)) return null;
  const ids = new Set(parsed.map((box) => box?.id));
  if (ids.size !== parsed.length) return null;
  return {
    kind: "image",
    media,
    width: width as number,
    height: height as number,
    boxes: parsed as ImageBox[],
  };
}

/** A sound of a non-empty media id and a positive whole `duration_ms`; null otherwise (ADR 0112). */
function parseAudio(payload: Record<string, unknown>): Content | null {
  const { media, duration_ms: durationMs } = payload;
  if (typeof media !== "string" || media === "") return null;
  if (!Number.isInteger(durationMs) || (durationMs as number) <= 0) return null;
  return { kind: "audio", media, durationMs: durationMs as number };
}

/**
 * The blocks of a stored card side, or null when [value] is not an array of blocks each with
 * a string `type`, a `v` that is a positive integer when present, an `id` that is text when
 * present, and a payload of its type's shape for a text, cloze, table or senses block at the
 * version this build reads, an older one upgraded first.
 */
export function parseContent(value: unknown): Content[] | null {
  if (!Array.isArray(value)) return null;
  const blocks: Content[] = [];
  for (const block of value as unknown[]) {
    if (!isRecord(block)) return null;
    const type = "type" in block ? block.type : null;
    const version = "v" in block ? block.v : 1;
    const id = "id" in block ? block.id : undefined;
    if (typeof type !== "string") return null;
    if (!Number.isInteger(version) || (version as number) < 1) return null;
    if (id !== undefined && typeof id !== "string") return null;
    if (!isKnownType(type) || (version as number) > blockVersion(type)) {
      blocks.push({ kind: "unsupported", type });
      continue;
    }
    const payload = upcastPayload(
      type,
      version as number,
      "payload" in block ? block.payload : null,
    );
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
            : type === "senses"
              ? parseSenses(payload)
              : type === "image"
                ? parseImage(payload)
                : parseAudio(payload);
    if (!parsed) return null;
    blocks.push(parsed);
  }
  return blocks;
}

/**
 * Whether a card with [front] is drawn whole rather than split: whether it holds a cloze, a
 * table, or a photo with a box over it (ADR 0109).
 */
export function isWholeCard(front: Content[]): boolean {
  return front.some(
    (block) =>
      block.kind === "cloze" ||
      block.kind === "table" ||
      (block.kind === "image" && block.boxes.length > 0),
  );
}

/** Whether a table block's cell at [row] and [column] is one to recall whole. */
function isBlank(blanks: TableBlank[], row: number, column: number): boolean {
  return blanks.some((blank) => blank.row === row && blank.column === column);
}

/**
 * A table block's cell at [row] and [column] as runs of its text, in order, as the phone's
 * `cellRuns`: one blank run when it is a whole blank, its text split around its spans when it
 * holds any, and otherwise one plain run.
 */
export function cellRuns(
  table: Extract<Content, { kind: "table" }>,
  row: number,
  column: number,
): CellRun[] {
  const text = table.rows[row]?.[column] ?? "";
  if (isBlank(table.blanks, row, column)) return [{ text, blank: true }];
  const inCell = table.spans
    .filter((span) => span.row === row && span.column === column)
    .sort((a, b) => a.start - b.start);
  const runs: CellRun[] = [];
  let at = 0;
  for (const span of inCell) {
    if (at < span.start) runs.push({ text: text.slice(at, span.start), blank: false });
    runs.push({ text: text.slice(span.start, span.end), blank: true });
    at = span.end;
  }
  if (at < text.length || runs.length === 0) runs.push({ text: text.slice(at), blank: false });
  return runs;
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
        case "image":
          return "사진";
        case "audio":
          return "소리";
        case "unsupported":
          return `[이 버전에서 표시할 수 없는 내용: ${block.type}]`;
      }
    })
    .join(" ");
}

/**
 * A card side as a screen reader reads it, as on the phone: each blank as its answer only when
 * [revealed], else as "빈칸", a table row by row, its cells joined by commas, a span in its
 * cell's text, and the blocks as sentences.
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
                .map((_, column) =>
                  cellRuns(block, row, column)
                    .map((run) => (run.blank ? blank(run.text) : run.text))
                    .join(""),
                )
                .join(", "),
            ),
          ].join(". ");
        case "image":
          // The photo, then each box as a blank, or its answer once revealed.
          return [
            "사진",
            ...block.boxes.map((box) =>
              box.answer !== null && box.answer.trim() !== "" ? blank(box.answer) : "빈칸",
            ),
          ].join(", ");
        default:
          return describeContent([block]);
      }
    })
    .join(". ");
}

/** A sound block, as [Content] holds one. */
export type AudioBlock = Extract<Content, { kind: "audio" }>;

/** The sounds among [blocks], in order (ADR 0112). */
export function audioOf(blocks: Content[]): AudioBlock[] {
  return blocks.filter((block): block is AudioBlock => block.kind === "audio");
}

/** How long a sound plays, as minutes and seconds rounded up to the second, `0:07`, as on the phone. */
export function audioLength(durationMs: number): string {
  const seconds = Math.ceil(durationMs / 1000);
  return `${String(Math.floor(seconds / 60))}:${String(seconds % 60).padStart(2, "0")}`;
}
