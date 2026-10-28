// The two-stage metrics: stage-1 structure, mark-to-blank, in-cell spans, the per-configuration
// summary, and the decision rule.
import assert from "node:assert/strict";
import {
  parseSectionTree,
  parseTruthSections,
  type Section,
} from "./sections.ts";
import {
  decide,
  type PageResult,
  scoreMarks,
  scoreSpans,
  scoreStructure,
  summarizePages,
  type TwoStageRow,
} from "./two_stage_metrics.ts";

/** A truth of a two-column table, its lines marked by pen, and a list. */
function truth() {
  const parsed = parseTruthSections([{
    title: "여러 나라의 비교",
    language: "ko",
    content_type: "comparison_table",
    lines: [],
    table: {
      columns: ["부여", "고구려"],
      rows: [{
        header: "정치",
        cells: [
          {
            lines: [{
              id: "t1",
              text: "5부족 연맹체",
              marks: [{ start: 0, end: 7, kind: "underline", ink: "pen" }],
              blanks: [{ start: 0, end: 7 }],
            }, {
              id: "t2",
              text: "여러 가들이 사출도 다스림",
              marks: [{ start: 7, end: 10, kind: "circle", ink: "pen" }],
              blanks: [{ start: 7, end: 10 }],
            }],
          },
          {
            lines: [{
              id: "t3",
              text: "5부 연맹체",
              marks: [],
              blanks: [{ start: 0, end: 6 }],
            }],
          },
        ],
      }],
    },
  }, {
    title: "더 기억할 점",
    language: "ko",
    content_type: "rule_list",
    lines: [{
      id: "t4",
      text: "동예는 책화로 갚았다",
      marks: [
        { start: 4, end: 6, kind: "circle", ink: "pen" },
        { start: 0, end: 11, kind: "star", ink: "pen" },
      ],
      blanks: [{ start: 4, end: 6 }],
    }],
    table: null,
  }]);
  if (parsed === null) throw new Error("the fixture is not a truth");
  return parsed;
}

const line = (id: string, text: string) => ({
  id,
  text,
  role: "fact",
  marks: [],
  key_terms: [],
});

function returned(sections: unknown[]): Section[] {
  const parsed = parseSectionTree(sections);
  if (parsed === null) throw new Error("the fixture is not stage 1's shape");
  return parsed;
}

Deno.test("structure: sections match by title, and columns, row headers and lines are found in place, spacing and punctuation aside", () => {
  const sections = returned([{
    title: "여러 나라의  비교.",
    language: "ko",
    content_type: "table",
    lines: [],
    table: {
      // The columns swapped: each line is still found under its own column.
      columns: ["고구려", "부여"],
      rows: [{
        header: "정치",
        cells: [
          { lines: [line("a", "5부 연맹체")] },
          { lines: [line("b", "5부족 연맹체")] },
        ],
      }],
    },
  }, {
    title: "덧붙임",
    language: "ko",
    content_type: "prose",
    lines: [line("c", "동예는 책화로 갚았다")],
    table: null,
  }]);
  const score = scoreStructure(sections, truth());
  assert.deepEqual(score.sections, { returned: 2, truth: 2, matched: 1 });
  assert.deepEqual(score.columns, { returned: 2, truth: 2, matched: 2 });
  assert.deepEqual(score.rows, { returned: 1, truth: 1, matched: 1 });
  // Two of the table's three lines, and none of the unmatched list's.
  assert.deepEqual(score.lines.matched, 2);
  assert.deepEqual(score.lines.truth, 4);
});

Deno.test("structure: a line returned under another column is not found", () => {
  const sections = returned([{
    title: "여러 나라의 비교",
    language: "ko",
    content_type: "comparison_table",
    lines: [],
    table: {
      columns: ["부여", "고구려"],
      rows: [{
        header: "정치",
        cells: [
          { lines: [line("a", "5부 연맹체")] },
          {
            lines: [
              line("b", "5부족 연맹체"),
              line("c", "여러 가들이 사출도 다스림"),
            ],
          },
        ],
      }],
    },
  }]);
  assert.equal(scoreStructure(sections, truth()).lines.matched, 0);
});

Deno.test("mark-to-blank: recall over the pen span marks, precision over the blanks on marked lines", () => {
  const score = scoreMarks([
    { line: "5부족 연맹체", text: "5부족 연맹체" }, // on its mark
    { line: "여러 가들이 사출도 다스림", text: "가들" }, // a marked line, off its mark
    { line: "5부 연맹체", text: "5부 연맹체" }, // an unmarked line: neither
    { line: "어디에도 없는 줄", text: "줄" }, // no truth line: neither
  ], truth());
  // Three span marks; the star is a line's mark, not a word to blank.
  assert.deepEqual(score.recall, { returned: 2, truth: 3, matched: 1 });
  assert.deepEqual(score.precision, { returned: 2, truth: 3, matched: 1 });
});

Deno.test("mark-to-blank: a mark blanked on another line than its own is not recalled", () => {
  const score = scoreMarks(
    [{ line: "동예는 책화로 갚았다", text: "사출도" }],
    truth(),
  );
  assert.equal(score.recall.matched, 0);
  assert.equal(score.precision.matched, 0);
});

Deno.test("in-cell spans: recall over the truth's blanks in table cells, precision over the spans returned on them", () => {
  const score = scoreSpans([
    { line: "5부족 연맹체", text: "5부족 연맹체" },
    { line: "5부 연맹체", text: "연맹체" }, // part of the blank only
    { line: "동예는 책화로 갚았다", text: "책화" }, // a list line: not a cell
  ], truth());
  assert.deepEqual(score.recall, { returned: 2, truth: 3, matched: 1 });
  assert.deepEqual(score.precision, { returned: 2, truth: 3, matched: 1 });
});

function page(overrides: Partial<PageResult>): PageResult {
  return {
    name: "page",
    vocabulary: null,
    notes: null,
    structure: null,
    marks: null,
    spans: null,
    shapes: [],
    composed: { judged: 0, unsupported: 0 },
    stage1Ms: null,
    totalMs: 1000,
    photoUsd: 0.001,
    spentUsd: 0.001,
    ...overrides,
  };
}

const notes = (coverage: number, cards: number, unsupported: number) => ({
  coverage,
  cards,
  unsupported,
  longAnswers: 0,
  examples: 0,
  inventedExamples: 0,
  bareExceptions: 0,
  tableBlanks: 0,
  tableBlanksCovered: 0,
  clozeBlanks: 0,
  clozeBlanksCovered: 0,
  annotations: 0,
  annotationsCarded: 0,
});

Deno.test("a configuration's row pools shape fidelity per shape, fabrication, cost per photo apart from spend, and latency to stage 1 and in total", () => {
  const row = summarizePages("B", [
    page({
      notes: notes(1, 4, 1),
      shapes: [
        { shape: "table_cells", valid: true },
        { shape: "cloze", valid: false },
      ],
      composed: { judged: 4, unsupported: 1 },
      stage1Ms: 1000,
      totalMs: 3000,
      photoUsd: 0.002,
      spentUsd: 0.01,
    }),
    page({
      notes: notes(0.5, 6, 0),
      shapes: [{ shape: "cloze", valid: true }],
      composed: { judged: 0, unsupported: 0 },
      stage1Ms: 2000,
      totalMs: 5000,
      photoUsd: 0.004,
      spentUsd: 0.02,
    }),
  ]);
  assert.equal(row.coverage, 0.75);
  assert.equal(row.unsupportedRate, 0.1);
  assert.equal(row.shapeFidelity, 2 / 3);
  assert.deepEqual(row.shapeFidelityByShape, { table_cells: 1, cloze: 0.5 });
  assert.equal(row.fabricationRate, 0.25);
  assert.equal(row.costPerPhotoUsd, 0.003);
  assert.equal(row.spentUsd, 0.03);
  assert.equal(row.stage1P50Ms, 1000);
  assert.equal(row.stage1P95Ms, 2000);
  assert.equal(row.totalP50Ms, 3000);
  assert.equal(row.totalP95Ms, 5000);
  // A share whose whole is 0 is null, not 0.
  assert.equal(row.markRecall, null);
  assert.equal(row.sectionF1, null);
});

Deno.test("the single call's row has no latency to stage 1 and no shapes", () => {
  const row = summarizePages("A", [page({ notes: notes(1, 2, 0) })]);
  assert.equal(row.stage1P50Ms, null);
  assert.equal(row.shapeFidelity, null);
  assert.equal(row.fabricationRate, null);
  assert.equal(row.totalP50Ms, 1000);
});

function row(overrides: Partial<TwoStageRow>): TwoStageRow {
  return {
    ...summarizePages("x", [page({ notes: notes(0.8, 10, 1) })]),
    ...overrides,
  };
}

Deno.test("the decision adopts only within 3 coverage points, at or below today's unsupported share, at 95% fidelity, and within 1.5 times today's p50", () => {
  const today = row({ coverage: 0.8, unsupportedRate: 0.1, totalP50Ms: 10000 });
  const edge = row({
    coverage: 0.77,
    unsupportedRate: 0.1,
    shapeFidelity: 0.95,
    totalP50Ms: 15000,
  });
  assert.deepEqual(decide(today, edge), {
    coverage: true,
    unsupported: true,
    fidelity: true,
    latency: true,
    adopt: true,
  });
  const cases: [
    string,
    Partial<TwoStageRow>,
    keyof ReturnType<typeof decide>,
  ][] = [
    ["coverage", { coverage: 0.769 }, "coverage"],
    ["unsupported", { unsupportedRate: 0.101 }, "unsupported"],
    ["fidelity", { shapeFidelity: 0.949 }, "fidelity"],
    ["no shapes", { shapeFidelity: null }, "fidelity"],
    ["latency", { totalP50Ms: 15001 }, "latency"],
  ];
  for (const [name, change, condition] of cases) {
    const decision = decide(today, { ...edge, ...change });
    assert.equal(decision[condition], false, name);
    assert.equal(decision.adopt, false, name);
  }
});
