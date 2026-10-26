/**
 * Scores the two-stage photo import (#414) against a page's ground truth, summarizes each
 * configuration, and applies the decision rule against today's single call.
 */

import {
  normalize,
  type NotesScore,
  percentile,
  type Score,
} from "./metrics.ts";
import {
  linesOf,
  type Section,
  SPAN_MARKS,
  spanText,
  type TruthLine,
} from "./sections.ts";
import type { LineBlank, Shape } from "./shapes.ts";

/**
 * How two texts the page prints are told equal: after `normalize`, with spaces and punctuation
 * dropped, so a transcription differing only in them still matches.
 */
export function textKey(text: string): string {
  return normalize(text).replace(/[\s\p{P}]/gu, "");
}

/** Counts a returned set is scored by against the truth: returned, truth, and those matching. */
export type Match = {
  readonly returned: number;
  readonly truth: number;
  readonly matched: number;
};

/**
 * One page's stage-1 structure against its truth. Sections match by title (`textKey`), each
 * once. Over matched table sections, the truth's columns and row headers found among the
 * returned ones, and its cell lines found in the returned cell of the same row and column; over
 * matched list sections, its lines found among the returned lines.
 */
export type StructureScore = {
  readonly sections: Match;
  readonly columns: Match;
  readonly rows: Match;
  readonly lines: Match;
};

/** Counts [truth] items found among [returned], each returned item used once. */
function matchKeys(
  returned: readonly string[],
  truth: readonly string[],
): Match {
  const left = returned.map(textKey);
  let matched = 0;
  for (const key of truth.map(textKey)) {
    const at = left.indexOf(key);
    if (at < 0) continue;
    left.splice(at, 1);
    matched += 1;
  }
  return { returned: returned.length, truth: truth.length, matched };
}

const NO_MATCH: Match = { returned: 0, truth: 0, matched: 0 };

function add(a: Match, b: Match): Match {
  return {
    returned: a.returned + b.returned,
    truth: a.truth + b.truth,
    matched: a.matched + b.matched,
  };
}

export function scoreStructure(
  returned: readonly Section[],
  truth: readonly Section<TruthLine>[],
): StructureScore {
  const left = [...returned];
  let columns = NO_MATCH;
  let rows = NO_MATCH;
  let lines = NO_MATCH;
  let matchedSections = 0;
  for (const page of truth) {
    const at = left.findIndex((section) =>
      textKey(section.title) === textKey(page.title)
    );
    if (at < 0) {
      // A section never returned still counts its truth against each recall.
      columns = add(columns, matchKeys([], page.table?.columns ?? []));
      rows = add(
        rows,
        matchKeys([], page.table?.rows.map((row) => row.header) ?? []),
      );
      lines = add(lines, matchKeys([], linesOf(page).map((line) => line.text)));
      continue;
    }
    const [section] = left.splice(at, 1);
    matchedSections += 1;
    if (page.table === null || section.table === null) {
      lines = add(
        lines,
        matchKeys(
          section.table === null ? section.lines.map((line) => line.text) : [],
          linesOf(page).map((line) => line.text),
        ),
      );
      columns = add(
        columns,
        matchKeys(section.table?.columns ?? [], page.table?.columns ?? []),
      );
      rows = add(
        rows,
        matchKeys(
          section.table?.rows.map((row) => row.header) ?? [],
          page.table?.rows.map((row) => row.header) ?? [],
        ),
      );
      continue;
    }
    const table = section.table;
    columns = add(columns, matchKeys(table.columns, page.table.columns));
    rows = add(
      rows,
      matchKeys(
        table.rows.map((row) => row.header),
        page.table.rows.map((row) => row.header),
      ),
    );
    const columnAt = (name: string) =>
      table.columns.findIndex((column) => textKey(column) === textKey(name));
    for (const row of page.table.rows) {
      const found = table.rows.find((candidate) =>
        textKey(candidate.header) === textKey(row.header)
      );
      row.cells.forEach((cell, c) => {
        const column = columnAt(page.table?.columns[c] ?? "");
        const returnedLines = found === undefined || column < 0
          ? []
          : found.cells[column]?.lines.map((line) => line.text) ?? [];
        lines = add(
          lines,
          matchKeys(returnedLines, cell.lines.map((line) => line.text)),
        );
      });
    }
  }
  return {
    sections: {
      returned: returned.length,
      truth: truth.length,
      matched: matchedSections,
    },
    columns,
    rows,
    lines,
  };
}

/**
 * Recall over the truth's items, `matched` those found; precision over the returned ones,
 * `matched` those correct.
 */
export type Retrieval = { readonly recall: Match; readonly precision: Match };

/**
 * The truth line a returned blank was made from, by the text of its stage-1 line, or undefined
 * when no truth line reads the same.
 */
function truthLineOf(
  blank: LineBlank,
  lines: readonly TruthLine[],
): TruthLine | undefined {
  const key = textKey(blank.line);
  return lines.find((line) => textKey(line.text) === key);
}

/**
 * Mark-to-blank: over the page's pen underlines, circles and highlights, those a returned blank
 * on the same line asks, its text equal to the mark's (`textKey`); and over the returned blanks on
 * a line the writer marked, those asking one of its marks.
 */
export function scoreMarks(
  blanks: readonly LineBlank[],
  truth: readonly Section<TruthLine>[],
): Retrieval {
  const lines = truth.flatMap(linesOf);
  const marked = (line: TruthLine) =>
    line.marks.filter((mark) =>
      mark.ink === "pen" && SPAN_MARKS.includes(mark.kind)
    ).map((mark) => textKey(spanText(line.text, mark)));
  let returned = 0;
  let matched = 0;
  const asked = new Map<TruthLine, string[]>();
  for (const blank of blanks) {
    const line = truthLineOf(blank, lines);
    if (line === undefined) continue;
    asked.set(line, [...asked.get(line) ?? [], textKey(blank.text)]);
    const marks = marked(line);
    if (marks.length === 0) continue;
    returned += 1;
    if (marks.includes(textKey(blank.text))) matched += 1;
  }
  let truthMarks = 0;
  let found = 0;
  for (const line of lines) {
    for (const mark of marked(line)) {
      truthMarks += 1;
      if ((asked.get(line) ?? []).includes(mark)) found += 1;
    }
  }
  return {
    recall: { returned, truth: truthMarks, matched: found },
    precision: { returned, truth: truthMarks, matched },
  };
}

/**
 * In-cell spans: over the blanks the truth names in table cells, those a span table blanks with
 * equal text on the same line; over the span table's blanks on a truth line, those equal to one
 * of its blanks.
 */
export function scoreSpans(
  blanks: readonly LineBlank[],
  truth: readonly Section<TruthLine>[],
): Retrieval {
  const lines = truth.flatMap((section) =>
    section.table === null ? [] : linesOf(section)
  );
  const expected = (line: TruthLine) =>
    line.blanks.map((blank) => textKey(spanText(line.text, blank)));
  let returned = 0;
  let correct = 0;
  const asked = new Map<TruthLine, string[]>();
  for (const blank of blanks) {
    const line = truthLineOf(blank, lines);
    if (line === undefined) continue;
    returned += 1;
    asked.set(line, [...asked.get(line) ?? [], textKey(blank.text)]);
    if (expected(line).includes(textKey(blank.text))) correct += 1;
  }
  let truthBlanks = 0;
  let found = 0;
  for (const line of lines) {
    for (const blank of expected(line)) {
      truthBlanks += 1;
      if ((asked.get(line) ?? []).includes(blank)) found += 1;
    }
  }
  return {
    recall: { returned, truth: truthBlanks, matched: found },
    precision: { returned, truth: truthBlanks, matched: correct },
  };
}

/** One page's outcome for one configuration. */
export type PageResult = {
  readonly name: string;
  readonly vocabulary: Score | null;
  readonly notes: NotesScore | null;
  /** Stage-1 structure, mark-to-blank and in-cell spans, on a page whose truth has sections. */
  readonly structure: StructureScore | null;
  /** Mark-to-blank over the returned blanks, and the blanks a span table returned. */
  readonly marks: Retrieval | null;
  readonly spans: Retrieval | null;
  /** Each stage-2 call: the shape it asked for and whether its reply was that shape, valid. */
  readonly shapes: readonly {
    readonly shape: Shape;
    readonly valid: boolean;
  }[];
  /** Composed questions and sentences the judge read, and those it found unsupported. */
  readonly composed: { readonly judged: number; readonly unsupported: number };
  /** Milliseconds to stage 1's sections, null for a single call. */
  readonly stage1Ms: number | null;
  /** Milliseconds to the cards: the single call, or stage 1 and the slowest default shape. */
  readonly totalMs: number;
  /** What the app pays a photo: the single call, or stage 1 and the default shapes. */
  readonly photoUsd: number;
  /** Everything the page's calls cost, the other shapes and the judge included. */
  readonly spentUsd: number;
};

/** One configuration's results over every page; each share is null where its whole is 0. */
export type TwoStageRow = {
  readonly label: string;
  readonly pages: number;
  readonly vocabularyF1: number | null;
  readonly coverage: number | null;
  readonly unsupportedRate: number | null;
  readonly inventedExamplesRate: number | null;
  readonly sectionF1: number | null;
  readonly columnMatch: number | null;
  readonly rowMatch: number | null;
  readonly lineMatch: number | null;
  readonly markRecall: number | null;
  readonly markPrecision: number | null;
  readonly spanRecall: number | null;
  readonly spanPrecision: number | null;
  /** Valid replies over the stage-2 calls, overall and per shape asked. */
  readonly shapeFidelity: number | null;
  readonly shapeFidelityByShape: Readonly<Partial<Record<Shape, number>>>;
  readonly fabricationRate: number | null;
  readonly composedJudged: number;
  readonly costPerPhotoUsd: number;
  readonly stage1P50Ms: number | null;
  readonly stage1P95Ms: number | null;
  readonly totalP50Ms: number;
  readonly totalP95Ms: number;
  readonly spentUsd: number;
};

function share(part: number, whole: number): number | null {
  return whole === 0 ? null : part / whole;
}

function sum<T>(items: readonly T[], pick: (item: T) => number): number {
  return items.reduce((total, item) => total + pick(item), 0);
}

function f1(match: Match): number | null {
  const precision = share(match.matched, match.returned);
  const recall = share(match.matched, match.truth);
  if (precision === null || recall === null) return null;
  return precision + recall === 0
    ? 0
    : (2 * precision * recall) / (precision + recall);
}

export function summarizePages(
  label: string,
  pages: readonly PageResult[],
): TwoStageRow {
  if (pages.length === 0) throw new RangeError(`${label} ran no page`);
  const vocabulary = pages.flatMap((page) =>
    page.vocabulary === null ? [] : [page.vocabulary]
  );
  const notes = pages.flatMap((page) =>
    page.notes === null ? [] : [page.notes]
  );
  const structures = pages.flatMap((page) =>
    page.structure === null ? [] : [page.structure]
  );
  const pooled = (pick: (score: StructureScore) => Match) =>
    structures.map(pick).reduce(add, NO_MATCH);
  const pool = (
    pick: (page: PageResult) => Match | undefined,
  ) => pages.flatMap((page) => pick(page) ?? []).reduce(add, NO_MATCH);
  const marks = {
    recall: pool((page) => page.marks?.recall),
    precision: pool((page) => page.marks?.precision),
  };
  const spans = {
    recall: pool((page) => page.spans?.recall),
    precision: pool((page) => page.spans?.precision),
  };
  const calls = pages.flatMap((page) => page.shapes);
  const byShape: Partial<Record<Shape, number>> = {};
  for (const shape of new Set(calls.map((call) => call.shape))) {
    const asked = calls.filter((call) => call.shape === shape);
    byShape[shape] = asked.filter((call) => call.valid).length / asked.length;
  }
  const stage1 = pages.flatMap((page) =>
    page.stage1Ms === null ? [] : [page.stage1Ms]
  );
  const totals = pages.map((page) => page.totalMs);
  const judged = sum(pages, (page) => page.composed.judged);
  return {
    label,
    pages: pages.length,
    vocabularyF1: vocabulary.length === 0
      ? null
      : sum(vocabulary, (score) => score.f1) / vocabulary.length,
    coverage: notes.length === 0
      ? null
      : sum(notes, (score) => score.coverage) / notes.length,
    unsupportedRate: share(
      sum(notes, (score) => score.unsupported),
      sum(notes, (score) => score.cards),
    ),
    inventedExamplesRate: share(
      sum(notes, (score) => score.inventedExamples),
      sum(notes, (score) => score.examples),
    ),
    sectionF1: f1(pooled((score) => score.sections)),
    columnMatch: recall(pooled((score) => score.columns)),
    rowMatch: recall(pooled((score) => score.rows)),
    lineMatch: recall(pooled((score) => score.lines)),
    markRecall: share(marks.recall.matched, marks.recall.truth),
    markPrecision: share(marks.precision.matched, marks.precision.returned),
    spanRecall: share(spans.recall.matched, spans.recall.truth),
    spanPrecision: share(spans.precision.matched, spans.precision.returned),
    shapeFidelity: share(
      calls.filter((call) => call.valid).length,
      calls.length,
    ),
    shapeFidelityByShape: byShape,
    fabricationRate: share(
      sum(pages, (page) => page.composed.unsupported),
      judged,
    ),
    composedJudged: judged,
    costPerPhotoUsd: sum(pages, (page) => page.photoUsd) / pages.length,
    stage1P50Ms: stage1.length === 0 ? null : percentile(stage1, 50),
    stage1P95Ms: stage1.length === 0 ? null : percentile(stage1, 95),
    totalP50Ms: percentile(totals, 50),
    totalP95Ms: percentile(totals, 95),
    spentUsd: sum(pages, (page) => page.spentUsd),
  };
}

function recall(match: Match): number | null {
  return share(match.matched, match.truth);
}

/** How far below today's coverage, in points of 100, a two-stage configuration may be. */
export const COVERAGE_DROP_POINTS = 3;
/** The least share of stage-2 calls whose reply is the requested shape, valid. */
export const MIN_SHAPE_FIDELITY = 0.95;
/** The most a two-stage configuration's p50 latency may be, as a multiple of today's. */
export const MAX_LATENCY_RATIO = 1.5;

/** Each condition of the decision rule, and whether [row] may be adopted over [today]. */
export type Decision = {
  readonly coverage: boolean;
  readonly unsupported: boolean;
  readonly fidelity: boolean;
  readonly latency: boolean;
  readonly adopt: boolean;
};

/**
 * The decision rule of #414: a two-stage configuration may replace today's single call only if
 * its coverage is no more than 3 points below, its unsupported share at or below, its shape
 * fidelity at least 95%, and its p50 latency at most 1.5 times today's. A share it lacks fails.
 */
export function decide(today: TwoStageRow, row: TwoStageRow): Decision {
  const coverage = row.coverage !== null && today.coverage !== null &&
    (today.coverage - row.coverage) * 100 <= COVERAGE_DROP_POINTS + 1e-9;
  const unsupported = row.unsupportedRate !== null &&
    today.unsupportedRate !== null &&
    row.unsupportedRate <= today.unsupportedRate + 1e-9;
  const fidelity = row.shapeFidelity !== null &&
    row.shapeFidelity >= MIN_SHAPE_FIDELITY - 1e-9;
  const latency = row.totalP50Ms <= MAX_LATENCY_RATIO * today.totalP50Ms;
  return {
    coverage,
    unsupported,
    fidelity,
    latency,
    adopt: coverage && unsupported && fidelity && latency,
  };
}
