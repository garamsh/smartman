// Stage 2's shapes: each reply checked against the section it was made from, and the cards,
// blanks and composed sentences the eval reads from it.
import assert from "node:assert/strict";
import { parseSectionTree, type Section } from "./sections.ts";
import {
  cardsOf,
  composedOf,
  lineBlanksOf,
  parseShape,
  type Shape,
  shapesFor,
} from "./shapes.ts";

const line = (id: string, text: string) => ({
  id,
  text,
  marks: [],
  key_terms: [],
});

/** A comparison table of two columns, one of its cells empty, and a list. */
function sections(): Section[] {
  const parsed = parseSectionTree([{
    title: "여러 나라의 비교",
    language: "ko",
    content_type: "comparison_table",
    lines: [],
    table: {
      columns: ["부여", "고구려"],
      rows: [
        {
          header: "정치",
          cells: [
            {
              lines: [
                line("a", "5부족 연맹체"),
                line("b", "여러 가들이 사출도 다스림"),
              ],
            },
            { lines: [line("c", "5부 연맹체")] },
          ],
        },
        {
          header: "풍습",
          cells: [{ lines: [line("d", "1책 12법")] }, { lines: [] }],
        },
      ],
    },
  }, {
    title: "더 기억할 점",
    language: "ko",
    content_type: "rule_list",
    lines: [line("e", "동예는 책화로 갚았다")],
    table: null,
  }]);
  if (parsed === null) throw new Error("the fixture is not stage 1's shape");
  return parsed;
}
const [TABLE, LIST] = sections();

/** A valid reply of each shape for the table, or for the list where the shape is the list's. */
function reply(shape: Shape): Record<string, unknown> {
  switch (shape) {
    case "table_cells":
      return {
        kind: shape,
        blanks: [{ row: 0, column: 0 }, { row: 1, column: 0 }],
      };
    case "table_spans":
      return {
        kind: shape,
        blanks: [
          { line_id: "a", start: 0, end: 7 },
          { line_id: "b", start: 7, end: 10 },
        ],
      };
    case "qa":
      return {
        kind: shape,
        cards: [
          {
            row: 0,
            column: 0,
            question: "부여의 정치 체제는?",
            composed: true,
          },
          {
            row: 0,
            column: 1,
            question: "고구려의 정치 체제는?",
            composed: true,
          },
          { row: 1, column: 0, question: "부여의 풍습은?", composed: true },
        ],
      };
    case "cloze":
      return {
        kind: shape,
        items: [{
          line_id: "e",
          sentence: "동예는 책화로 갚았다",
          blanks: ["책화"],
          composed: false,
        }],
      };
    case "vocabulary":
      return {
        kind: shape,
        cards: [{
          kind: "vocabulary",
          type: "concept",
          front: "apple",
          answer: null,
          topic: "Unit 1",
          senses: [{ labels: [], meaning: "사과", examples: [] }],
          extras: [],
          pronunciation: null,
          examples: [],
          table: null,
          cloze: null,
        }],
      };
  }
}

const sectionOf = (shape: Shape) => shape === "cloze" ? LIST : TABLE;

Deno.test("a table section asks four shapes, whole-cell blanks first; a vocabulary list one; any other section a cloze", () => {
  assert.deepEqual(shapesFor("comparison_table"), [
    "table_cells",
    "table_spans",
    "qa",
    "cloze",
  ]);
  assert.deepEqual(shapesFor("table"), shapesFor("comparison_table"));
  assert.deepEqual(shapesFor("vocabulary_list"), ["vocabulary"]);
  assert.deepEqual(shapesFor("rule_list"), ["cloze"]);
  assert.deepEqual(shapesFor("prose"), ["cloze"]);
});

Deno.test("each shape's valid reply is read, and a reply of another shape than the one asked is refused", () => {
  for (
    const shape of [
      "table_cells",
      "table_spans",
      "qa",
      "cloze",
      "vocabulary",
    ] as const
  ) {
    assert.equal(
      parseShape(shape, reply(shape), sectionOf(shape))?.kind,
      shape,
      `${shape} is read`,
    );
    const other = shape === "qa" ? "table_cells" : "qa";
    assert.equal(
      parseShape(other, reply(shape), sectionOf(shape)),
      null,
      `${shape} is not ${other}`,
    );
  }
});

Deno.test("a shape breaking what its section allows is refused", () => {
  const broken: [Shape, Section, (value: Record<string, unknown>) => void][] = [
    ["table_cells", TABLE, (value) => {
      value.blanks = [{ row: 1, column: 1 }]; // the empty cell
    }],
    ["table_cells", TABLE, (value) => {
      value.blanks = [{ row: 2, column: 0 }]; // no third row
    }],
    ["table_cells", TABLE, (value) => {
      value.blanks = [{ row: 0, column: 0 }, { row: 0, column: 0 }];
    }],
    ["table_cells", TABLE, (value) => {
      value.blanks = [];
    }],
    ["table_cells", LIST, () => {}], // a list has no table
    ["table_spans", TABLE, (value) => {
      value.blanks = [{ line_id: "a", start: 0, end: 8 }]; // past the line
    }],
    ["table_spans", TABLE, (value) => {
      value.blanks = [
        { line_id: "a", start: 0, end: 4 },
        { line_id: "a", start: 3, end: 7 },
      ];
    }],
    ["table_spans", TABLE, (value) => {
      value.blanks = [{ line_id: "e", start: 0, end: 2 }]; // another section's line
    }],
    ["qa", TABLE, (value) => {
      (value.cards as unknown[]).pop(); // a cell holding lines left unasked
    }],
    ["qa", TABLE, (value) => {
      (value.cards as unknown[]).push({
        row: 1,
        column: 1,
        question: "고구려의 풍습은?",
        composed: true,
      }); // the empty cell asked
    }],
    ["cloze", LIST, (value) => {
      value.items = []; // the line left without its sentence
    }],
    ["cloze", LIST, (value) => {
      const [item] = value.items as Record<string, unknown>[];
      item.sentence = "동예는 다른 부족을 침범하면 책화로 갚았다"; // reworded, not composed
    }],
    ["cloze", LIST, (value) => {
      const [item] = value.items as Record<string, unknown>[];
      item.blanks = [];
    }],
    ["cloze", LIST, (value) => {
      const [item] = value.items as Record<string, unknown>[];
      item.blanks = ["책벌"]; // not in the sentence
    }],
    ["vocabulary", TABLE, (value) => {
      const [card] = value.cards as Record<string, unknown>[];
      card.kind = "note";
      card.answer = "사과";
      card.senses = [];
    }],
    ["vocabulary", TABLE, (value) => {
      value.cards = [];
    }],
  ];
  broken.forEach(([shape, section, breakIt], i) => {
    const value = reply(shape);
    breakIt(value);
    assert.equal(parseShape(shape, value, section), null, `${i}: ${shape}`);
  });
});

Deno.test("a composed cloze sentence may reword its line, and its blanks are read from the sentence", () => {
  const value = reply("cloze");
  const [item] = value.items as Record<string, unknown>[];
  item.sentence = "동예는 다른 부족을 침범하면 책화로 갚았다";
  item.blanks = ["책화"];
  item.composed = true;
  const output = parseShape("cloze", value, LIST);
  assert.ok(output !== null);
  assert.deepEqual(cardsOf(output, LIST), [{
    type: "cloze",
    front: "동예는 다른 부족을 침범하면 ___로 갚았다",
    answer: "책화",
    cloze: { answers: ["책화"] },
  }]);
  assert.deepEqual(lineBlanksOf(output, LIST), [{
    line: "동예는 책화로 갚았다",
    text: "책화",
  }]);
  assert.deepEqual(composedOf(output), [
    "동예는 다른 부족을 침범하면 책화로 갚았다",
  ]);
});

Deno.test("cloze blanks are the texts they hide, found in the sentence in order, a repeated text at its next place", () => {
  const value = reply("cloze");
  const [item] = value.items as Record<string, unknown>[];
  item.sentence = "책화는 책화로 갚았다";
  item.blanks = ["책화", "책화", "갚았다"];
  item.composed = true;
  const output = parseShape("cloze", value, LIST);
  assert.ok(output !== null);
  assert.deepEqual(cardsOf(output, LIST)[0].front, "___는 ___로 ___");
  item.blanks = ["갚았다", "책화"];
  assert.equal(
    parseShape("cloze", value, LIST),
    null,
    "blanks out of the sentence's order are refused",
  );
});

Deno.test("table shapes make one table card with the row headers as its first column; questions answer with their cell's lines", () => {
  const cells = parseShape("table_cells", reply("table_cells"), TABLE);
  assert.ok(cells !== null);
  const [card] = cardsOf(cells, TABLE);
  assert.deepEqual(card.table, {
    columns: ["", "부여", "고구려"],
    rows: [
      ["정치", "5부족 연맹체\n여러 가들이 사출도 다스림", "5부 연맹체"],
      ["풍습", "1책 12법", ""],
    ],
    blanks: [{ row: 0, column: 1 }, { row: 1, column: 1 }],
  });
  assert.equal(card.front, "여러 나라의 비교");
  const spans = parseShape("table_spans", reply("table_spans"), TABLE);
  assert.ok(spans !== null);
  assert.deepEqual(cardsOf(spans, TABLE)[0].table?.blanks, [{
    row: 0,
    column: 1,
  }]);
  assert.deepEqual(lineBlanksOf(spans, TABLE), [
    { line: "5부족 연맹체", text: "5부족 연맹체" },
    { line: "여러 가들이 사출도 다스림", text: "사출도" },
  ]);
  assert.deepEqual(composedOf(spans), []);
  const qa = parseShape("qa", reply("qa"), TABLE);
  assert.ok(qa !== null);
  assert.deepEqual(cardsOf(qa, TABLE)[0], {
    type: "concept",
    front: "부여의 정치 체제는?",
    answer: "5부족 연맹체\n여러 가들이 사출도 다스림",
  });
  assert.equal(composedOf(qa).length, 3);
});
