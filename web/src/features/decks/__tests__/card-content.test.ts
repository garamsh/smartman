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
