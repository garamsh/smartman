import { describe, expect, it } from "vitest";

import { describeContent, isWholeCard, parseContent, spokenContent } from "../card-content";

// The cases of the app's `app/test/deck/content_test.dart`: both clients read one stored shape.
const cloze = { type: "cloze", payload: { text: "___ is in ___", answers: ["Paris", "France"] } };
const table = (rows: unknown, blanks: unknown) => ({
  type: "table",
  payload: { columns: ["Capital", "Country"], rows, blanks },
});
const rows = [["Paris", "France"]];
const cell = [{ row: 0, column: 0 }];

describe("a card side's blocks", () => {
  it("read a cloze and a table as typed blocks beside text", () => {
    expect(
      parseContent([{ type: "text", payload: { text: "Capitals" } }, cloze, table(rows, cell)]),
    ).toEqual([
      { kind: "text", text: "Capitals" },
      { kind: "cloze", text: "___ is in ___", answers: ["Paris", "France"] },
      { kind: "table", columns: ["Capital", "Country"], rows, blanks: cell },
    ]);
  });

  it("refuse a cloze or a table that breaks its shape, where a whole one is read", () => {
    for (const broken of [
      { type: "cloze", payload: { text: "___ and ___", answers: ["one"] } },
      { type: "cloze", payload: { text: "___", answers: [" "] } },
      table([["1"]], cell),
      table(rows, []),
      table(rows, [{ row: 1, column: 0 }]),
      table([["", "France"]], cell),
      table(rows, [...cell, ...cell]),
    ]) {
      expect(parseContent([broken]), JSON.stringify(broken)).toBeNull();
    }
    // Control: each whole.
    expect(parseContent([cloze])).not.toBeNull();
    expect(parseContent([table(rows, cell)])).not.toBeNull();
  });

  it("read as their filled text, or as a screen reader reads them, and only a cloze or a table makes a whole card", () => {
    const blocks =
      parseContent([{ type: "text", payload: { text: "Capitals" } }, table(rows, cell)]) ?? [];
    const sentence = parseContent([cloze]) ?? [];

    expect(describeContent(sentence)).toBe("Paris is in France");
    expect(describeContent(blocks)).toBe("Capitals Capital | Country\nParis | France");
    expect(spokenContent(sentence, false)).toBe("빈칸 is in 빈칸");
    expect(spokenContent(blocks, false)).toBe("Capitals. Capital, Country. 빈칸, France");
    expect(spokenContent(blocks, true)).toBe("Capitals. Capital, Country. Paris, France");
    expect(isWholeCard(sentence)).toBe(true);
    // Control: text alone, a v6 cloze's "___" included, is split.
    expect(isWholeCard([{ kind: "text", text: "___ is in France" }])).toBe(false);
  });
});

// The cases of the app's senses tests in `content_test.dart`.
describe("a senses block", () => {
  const sense = (fields: Record<string, unknown> = {}) => ({
    labels: [],
    meaning: "사과",
    examples: [],
    ...fields,
  });
  const senses = (value: unknown) => [{ type: "senses", payload: { senses: value } }];

  it("is read with each sense's labels, meaning and examples", () => {
    expect(
      parseContent(
        senses([
          sense({
            labels: [
              { kind: "part_of_speech", category: "noun", text: "명" },
              { kind: "other", category: null, text: "사물" },
            ],
            meaning: "기차",
            examples: ["기차를 타다"],
          }),
        ]),
      ),
    ).toEqual([
      {
        kind: "senses",
        senses: [
          {
            labels: [
              { kind: "part_of_speech", category: "noun", text: "명" },
              { kind: "other", category: null, text: "사물" },
            ],
            meaning: "기차",
            examples: ["기차를 타다"],
          },
        ],
      },
    ]);
  });

  it("is refused when it breaks its shape, where a whole one is read", () => {
    for (const broken of [
      senses([]),
      senses("사과"),
      senses([sense({ meaning: " " })]),
      senses([sense({ meaning: null })]),
      senses([sense({ examples: [1] })]),
      senses([sense({ labels: [{ kind: "part_of_speech", category: "gerund", text: "동" }] })]),
      senses([sense({ labels: [{ kind: "other", category: "noun", text: "사물" }] })]),
      senses([sense({ labels: [{ kind: "other", category: null, text: "" }] })]),
      senses([{ pos: "[명]", meaning: "사과" }]),
    ]) {
      expect(parseContent(broken), JSON.stringify(broken)).toBeNull();
    }
    // Control: a whole one, with a label of each kind.
    expect(
      parseContent(
        senses([
          sense({
            labels: [
              { kind: "part_of_speech", category: "noun", text: "명" },
              { kind: "other", category: null, text: "사물" },
            ],
          }),
        ]),
      ),
    ).not.toBeNull();
  });

  it("reads the back the server's senses migration writes, as supabase/tests/senses_migration_test.sql states it", () => {
    const migrated =
      '[{"type": "senses", "payload": {"senses": [{"labels": [{"kind": "part_of_speech", "text": "명", "category": "noun"}], "meaning": "사과", "examples": []}, {"labels": [{"kind": "part_of_speech", "text": "동", "category": "verb"}], "meaning": "먹다", "examples": []}]}}]';
    const blocks = parseContent(JSON.parse(migrated));
    expect(blocks).toEqual([
      {
        kind: "senses",
        senses: [
          {
            labels: [{ kind: "part_of_speech", category: "noun", text: "명" }],
            meaning: "사과",
            examples: [],
          },
          {
            labels: [{ kind: "part_of_speech", category: "verb", text: "동" }],
            meaning: "먹다",
            examples: [],
          },
        ],
      },
    ]);
    expect(describeContent(blocks ?? [])).toBe("[명] 사과\n[동] 먹다");
  });

  it("reads as one line per sense, each label in brackets and a space before the meaning, a part of speech by its short form", () => {
    const blocks =
      parseContent(
        senses([
          sense({
            labels: [{ kind: "part_of_speech", category: "verb", text: "v." }],
            meaning: "살다, 거주하다",
          }),
          sense({
            labels: [{ kind: "other", category: null, text: "사물" }],
            meaning: "철도 위를 다니는 긴 차",
          }),
          sense({ meaning: "사과" }),
        ]),
      ) ?? [];
    expect(describeContent(blocks)).toBe(
      "[동] 살다, 거주하다\n[사물] 철도 위를 다니는 긴 차\n사과",
    );
  });
});
