// Stage 1's parser: a page's sections as the model returns them, and a ground truth's.
import assert from "node:assert/strict";
import { flatOf, parseSections, parseTruthSections } from "./sections.ts";

const line = (
  id: string,
  text: string,
  row: number,
  column: number,
  extra: Record<string, unknown> = {},
) => ({
  id,
  text,
  row,
  column,
  marks: [],
  key_terms: [],
  ...extra,
});

/**
 * A page of a comparison table whose cells hold bullet lines, one of them empty, and a list, as
 * stage 1 writes it: each table line names its cell, each list line none.
 */
function page() {
  return {
    kind: "sections",
    sections: [
      {
        title: "여러 나라의 비교",
        language: "ko",
        content_type: "comparison_table",
        columns: ["부여", "고구려"],
        rows: ["정치", "풍습"],
        lines: [
          line("s1-r1-c1-l1", "5부족 연맹체", 0, 0, {
            marks: [{ start: 0, end: 7, kind: "underline", ink: "pen" }],
            key_terms: [{ start: 0, end: 7, source: "mark" }],
          }),
          line("s1-r1-c2-l1", "5부 연맹체", 0, 1),
          line("s1-r1-c1-l2", "여러 가들이 사출도 다스림", 0, 0),
          line("s1-r2-c1-l1", "1책 12법", 1, 0),
        ],
      },
      {
        title: "더 기억할 점",
        language: "ko",
        content_type: "rule_list",
        columns: [] as string[],
        rows: [] as string[],
        lines: [line("s2-l1", "  동예는 책화로 갚았다  ", -1, -1)],
      },
    ],
  };
}

Deno.test("stage 1's flat table is read as rows of cells, each holding its lines in order, and a list as its lines", () => {
  const sections = parseSections(page());
  assert.ok(sections !== null);
  assert.equal(sections.length, 2);
  const table = sections[0].table;
  assert.deepEqual(table?.columns, ["부여", "고구려"]);
  assert.deepEqual(table?.rows.map((row) => row.header), ["정치", "풍습"]);
  assert.deepEqual(
    table?.rows.map((row) =>
      row.cells.map((cell) => cell.lines.map((one) => one.id))
    ),
    [[["s1-r1-c1-l1", "s1-r1-c1-l2"], ["s1-r1-c2-l1"]], [["s1-r2-c1-l1"], []]],
  );
  assert.deepEqual(sections[0].lines, []);
  assert.deepEqual(table?.rows[0].cells[0].lines[0].marks, [
    { start: 0, end: 7, kind: "underline", ink: "pen" },
  ]);
  assert.deepEqual(
    table?.rows[0].cells[0].lines[0].key_terms,
    [{ start: 0, end: 7, source: "mark" }],
  );
  assert.equal(sections[1].table, null);
  assert.equal(sections[1].lines[0].text, "동예는 책화로 갚았다", "trimmed");
});

Deno.test("a section stage 2 is given in the flat shape reads back as the same section", () => {
  const sections = parseSections(page());
  assert.ok(sections !== null);
  const again = parseSections({
    kind: "sections",
    sections: sections.map(flatOf),
  });
  assert.deepEqual(again, sections);
  assert.deepEqual(
    (flatOf(sections[0]).lines as { id: string; row: number }[]).map((one) =>
      `${one.id}@${one.row}`
    ),
    ["s1-r1-c1-l1@0", "s1-r1-c1-l2@0", "s1-r1-c2-l1@0", "s1-r2-c1-l1@1"],
  );
});

Deno.test("stage 1's reply is refused when a section breaks its content type, a line its cell, a line id repeats, or a span leaves its line", () => {
  // Control: the unbroken page parses, so each refusal below is the one change it makes.
  assert.notEqual(parseSections(page()), null);
  const broken: [string, (value: ReturnType<typeof page>) => void][] = [
    ["another kind", (value) => {
      value.kind = "table_cells";
    }],
    ["a list section with columns and rows", (value) => {
      value.sections[1].columns = ["a"];
      value.sections[1].rows = ["b"];
      value.sections[1].lines[0].row = 0;
      value.sections[1].lines[0].column = 0;
    }],
    ["a list section with no line", (value) => {
      value.sections[1].lines = [];
    }],
    ["a list line given a cell", (value) => {
      value.sections[1].lines[0].row = 0;
    }],
    ["a table section without columns or rows", (value) => {
      value.sections[0].columns = [];
      value.sections[0].rows = [];
      for (const one of value.sections[0].lines) {
        one.row = -1;
        one.column = -1;
      }
    }],
    ["a table line past the last column", (value) => {
      value.sections[0].lines[1].column = 2;
    }],
    ["a table line past the last row", (value) => {
      value.sections[0].lines[3].row = 2;
    }],
    ["a table line outside any cell", (value) => {
      value.sections[0].lines[3].row = -1;
    }],
    ["a line id given twice", (value) => {
      value.sections[1].lines[0].id = "s1-r1-c1-l1";
    }],
    ["a mark past the line's end", (value) => {
      (value.sections[0].lines[0].marks as { end: number }[])[0].end = 8;
    }],
    ["an empty key term", (value) => {
      (value.sections[0].lines[0].key_terms as { start: number }[])[0].start =
        7;
    }],
    ["an unknown content type", (value) => {
      value.sections[1].content_type = "outline";
    }],
    ["a key outside the schema", (value) => {
      (value.sections[1].lines[0] as Record<string, unknown>).blanks = [];
    }],
    ["a section in the nested shape", (value) => {
      (value.sections[1] as Record<string, unknown>).table = null;
    }],
  ];
  for (const [name, breakIt] of broken) {
    const value = page();
    breakIt(value);
    assert.equal(parseSections(value), null, name);
  }
});

Deno.test("a ground truth's sections carry the spans to blank, and a truth line without one is refused", () => {
  const truth = [{
    title: "더 기억할 점",
    language: "ko",
    content_type: "rule_list",
    lines: [{
      id: "s2-l1",
      text: "동예는 책화로 갚았다",
      marks: [{ start: 4, end: 6, kind: "circle", ink: "pen" }],
      blanks: [{ start: 4, end: 6 }],
    }],
    table: null,
  }];
  const parsed = parseTruthSections(truth);
  assert.deepEqual(parsed?.[0].lines[0].blanks, [{ start: 4, end: 6 }]);
  truth[0].lines[0].blanks = [];
  assert.equal(parseTruthSections(truth), null);
});
