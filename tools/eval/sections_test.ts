// Stage 1's parser: a page's sections as the model returns them, and a ground truth's.
import assert from "node:assert/strict";
import { linesOf, parseSections, parseTruthSections } from "./sections.ts";

const line = (
  id: string,
  text: string,
  extra: Record<string, unknown> = {},
) => ({
  id,
  text,
  marks: [],
  key_terms: [],
  ...extra,
});

/** A page of a comparison table whose cells hold bullet lines, and a list. */
function page() {
  return {
    kind: "sections",
    sections: [
      {
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
                lines: [
                  line("s1-r1-c1-l1", "5부족 연맹체", {
                    marks: [{
                      start: 0,
                      end: 7,
                      kind: "underline",
                      ink: "pen",
                    }],
                    key_terms: [{ start: 0, end: 7, source: "mark" }],
                  }),
                  line("s1-r1-c1-l2", "여러 가들이 사출도 다스림"),
                ],
              },
              { lines: [line("s1-r1-c2-l1", "5부 연맹체")] },
            ],
          }],
        },
      },
      {
        title: "더 기억할 점",
        language: "ko",
        content_type: "rule_list",
        lines: [line("s2-l1", "  동예는 책화로 갚았다  ")],
        table: null,
      },
    ],
  };
}

Deno.test("stage 1's sections are read with a table's cells of lines, a list's lines, and each line's marks and key terms", () => {
  const sections = parseSections(page());
  assert.ok(sections !== null);
  assert.equal(sections.length, 2);
  assert.deepEqual(sections[0].table?.columns, ["부여", "고구려"]);
  assert.deepEqual(
    linesOf(sections[0]).map((one) => one.id),
    ["s1-r1-c1-l1", "s1-r1-c1-l2", "s1-r1-c2-l1"],
  );
  assert.deepEqual(sections[0].table?.rows[0].cells[0].lines[0].marks, [
    { start: 0, end: 7, kind: "underline", ink: "pen" },
  ]);
  assert.deepEqual(
    sections[0].table?.rows[0].cells[0].lines[0].key_terms,
    [{ start: 0, end: 7, source: "mark" }],
  );
  assert.equal(sections[1].table, null);
  assert.equal(sections[1].lines[0].text, "동예는 책화로 갚았다", "trimmed");
});

Deno.test("stage 1's reply is refused when a section breaks its content type, a row its width, a line id repeats, or a span leaves its line", () => {
  // Control: the unbroken page parses, so each refusal below is the one change it makes.
  assert.notEqual(parseSections(page()), null);
  const broken: [string, (value: ReturnType<typeof page>) => void][] = [
    ["another kind", (value) => {
      value.kind = "table_cells";
    }],
    ["a table section with lines", (value) => {
      value.sections[0].lines = [line("s1-l9", "더 있음")];
    }],
    ["a list section with a table", (value) => {
      (value.sections[1] as Record<string, unknown>).table =
        value.sections[0].table;
    }],
    ["a list section with no line", (value) => {
      value.sections[1].lines = [];
    }],
    ["a table section without its table", (value) => {
      (value.sections[0] as Record<string, unknown>).table = null;
    }],
    ["a row narrower than the columns", (value) => {
      value.sections[0].table?.rows[0].cells.pop();
    }],
    ["a line id given twice", (value) => {
      value.sections[1].lines[0].id = "s1-r1-c1-l1";
    }],
    ["a mark past the line's end", (value) => {
      const first = value.sections[0].table?.rows[0].cells[0].lines[0];
      if (first !== undefined) (first.marks as { end: number }[])[0].end = 8;
    }],
    ["an empty key term", (value) => {
      const first = value.sections[0].table?.rows[0].cells[0].lines[0];
      if (first !== undefined) {
        (first.key_terms as { start: number }[])[0].start = 7;
      }
    }],
    ["an unknown content type", (value) => {
      value.sections[1].content_type = "outline";
    }],
    ["a key outside the schema", (value) => {
      (value.sections[1].lines[0] as Record<string, unknown>).blanks = [];
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
