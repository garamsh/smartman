import { describe, expect, it } from "vitest";

import {
  blockVersion,
  describeContent,
  isWholeCard,
  parseContent,
  spokenContent,
  upcastPayload,
} from "../card-content";

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

  it("read as their filled text, or as a screen reader reads them, and a cloze or a table makes a whole card where text does not", () => {
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

// ADR 0106's block versions, as the app's `content_test.dart` states them.
describe("a block's version and id", () => {
  const known = [
    { type: "text", payload: { text: "bonjour" } },
    cloze,
    table(rows, cell),
    {
      type: "senses",
      payload: { senses: [{ labels: [], meaning: "기차", examples: [] }] },
    },
    { type: "image", payload: { media: "m1", width: 4, height: 3, boxes: [] } },
  ];

  it("reads each known type at v1 with or without the field, and with an id", () => {
    for (const block of known) {
      const read = parseContent([block]);
      expect(read, block.type).not.toBeNull();
      expect(parseContent([{ ...block, v: 1 }]), block.type).toEqual(read);
      expect(parseContent([{ ...block, v: 1, id: "b1" }]), block.type).toEqual(read);
    }
  });

  it("shows a known type above the version it reads, or an unknown type, as a placeholder", () => {
    for (const block of known) {
      expect(parseContent([{ ...block, v: 2 }]), block.type).toEqual([
        { kind: "unsupported", type: block.type },
      ]);
    }
    expect(parseContent([{ type: "audio", v: 1, payload: { media: "m1" } }])).toEqual([
      { kind: "unsupported", type: "audio" },
    ]);
  });

  it("refuses a v that is not a positive integer, or an id that is not text", () => {
    const text = { type: "text", payload: { text: "cat" } };
    for (const broken of [
      { ...text, v: 0 },
      { ...text, v: "1" },
      { ...text, v: 1.5 },
      { ...text, v: 1, id: 7 },
    ]) {
      expect(parseContent([broken]), JSON.stringify(broken)).toBeNull();
    }
    expect(parseContent([{ ...text, v: 1, id: "a" }]), "control").not.toBeNull();
  });

  it("upgrades an older payload one step per version", () => {
    const steps = {
      text: [
        (payload: unknown) => ({ body: (payload as { text: string }).text }),
        (payload: unknown) => ({ body: (payload as { body: string }).body.trim() }),
      ],
      cloze: [],
      table: [],
      senses: [],
      image: [],
    };
    expect(blockVersion("text", steps)).toBe(3);
    expect(upcastPayload("text", 1, { text: " cat " }, steps)).toEqual({ body: "cat" });
    expect(upcastPayload("text", 2, { body: " cat " }, steps)).toEqual({ body: "cat" });
    expect(upcastPayload("text", 3, { body: "cat" }, steps)).toEqual({ body: "cat" });
    for (const type of ["text", "cloze", "table", "senses", "image"] as const) {
      expect(blockVersion(type), type).toBe(1);
    }
  });
});

// The cases of the app's image tests in `content_test.dart` (ADR 0109).
describe("an image block", () => {
  const image = (payload: Record<string, unknown>) => ({ type: "image", payload });
  const box = (fields: Record<string, unknown>) =>
    image({ media: "m1", width: 4, height: 3, boxes: [fields] });
  const whole = { id: "1", x: 0.1, y: 0.2, w: 0.3, h: 0.4 };

  it("reads its photo, size and boxes in fractions of the image, past fields it does not know", () => {
    expect(
      parseContent([
        image({
          media: "m1",
          width: 1200,
          height: 800,
          boxes: [
            { ...whole, answer: "Paris", shape: "oval" },
            { id: "2", x: 0.5, y: 0.5, w: 0.5, h: 0.5 },
          ],
          crop: { x: 0 },
        }),
      ]),
    ).toEqual([
      {
        kind: "image",
        media: "m1",
        width: 1200,
        height: 800,
        boxes: [
          { ...whole, answer: "Paris" },
          { id: "2", x: 0.5, y: 0.5, w: 0.5, h: 0.5, answer: null },
        ],
      },
    ]);
  });

  it("is refused when it breaks its shape, where a whole one is read", () => {
    for (const broken of [
      image({ width: 4, height: 3, boxes: [] }),
      image({ media: "", width: 4, height: 3, boxes: [] }),
      image({ media: "m1", width: 0, height: 3, boxes: [] }),
      image({ media: "m1", width: 4.5, height: 3, boxes: [] }),
      image({ media: "m1", width: 4, height: 3 }),
      box({ x: 0, y: 0, w: 1, h: 1 }),
      box({ ...whole, x: -0.1 }),
      box({ ...whole, w: 0 }),
      box({ ...whole, x: 0.6, w: 0.5 }),
      box({ ...whole, y: 0.6, h: 0.5 }),
      box({ ...whole, answer: 3 }),
      image({ media: "m1", width: 4, height: 3, boxes: [whole, whole] }),
    ]) {
      expect(parseContent([broken]), JSON.stringify(broken)).toBeNull();
    }
    // Control: each whole.
    expect(parseContent([box(whole)])).not.toBeNull();
    expect(parseContent([image({ media: "m1", width: 4, height: 3, boxes: [] })])).not.toBeNull();
  });

  it("reads as a photo with each box a blank until revealed, and makes a whole card only with a box", () => {
    const boxed = parseContent([box({ ...whole, answer: "Paris" })]) ?? [];
    const bare = parseContent([image({ media: "m1", width: 4, height: 3, boxes: [] })]) ?? [];

    expect(describeContent(boxed)).toBe("사진");
    expect(spokenContent(boxed, false)).toBe("사진, 빈칸");
    expect(spokenContent(boxed, true)).toBe("사진, Paris");
    expect(isWholeCard(boxed)).toBe(true);
    // Control: the same photo without a box is split.
    expect(isWholeCard(bare)).toBe(false);
  });
});
