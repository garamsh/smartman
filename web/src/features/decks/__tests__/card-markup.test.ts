import { describe, expect, it } from "vitest";

import { filled, hasBlanks, runsOf, spoken, tableOf } from "../card-markup";

// The same cases as the app's `app/test/deck/card_markup_test.dart`: both clients read one markup.
describe("a whole card's markup", () => {
  it("is a blank holding its trimmed answer, and a front without one is no whole card", () => {
    expect(hasBlanks("The capital of France is {{c:: Paris }}.")).toBe(true);
    expect(filled("The capital of France is {{c:: Paris }}.")).toBe(
      "The capital of France is Paris.",
    );
    expect(runsOf("{{c::A}} and {{c::B}}!")).toEqual([
      { kind: "blank", answer: "A" },
      { kind: "plain", text: " and " },
      { kind: "blank", answer: "B" },
      { kind: "plain", text: "!" },
    ]);
    expect(hasBlanks("The capital of France is ___")).toBe(false);
    expect(hasBlanks("{{c::  }}")).toBe(false);
  });

  it("makes pipe lines a table, its rows above a --- row its header, short rows filled out", () => {
    expect(tableOf("| 품사 | 예 |\n| --- | :---: |\n| 명사 | {{c::사과}} |\n| 동사 |\n")).toEqual({
      rows: [
        ["품사", "예"],
        ["명사", "{{c::사과}}"],
        ["동사", ""],
      ],
      headerRows: 1,
    });
    expect(tableOf("| a | b |\n| c | d |")?.headerRows).toBe(0);
    expect(tableOf("| a | b |\nc d")).toBeNull();
    expect(tableOf("| a | b |")).toBeNull();
  });

  it("is read with its blanks as 빈칸 until revealed, a table row by row", () => {
    expect(spoken("{{c::Paris}} is in France", false)).toBe("빈칸 is in France");
    expect(spoken("{{c::Paris}} is in France", true)).toBe("Paris is in France");
    expect(spoken("| 품사 | 예 |\n| --- | --- |\n| 명사 | {{c::사과}} |", false)).toBe(
      "품사, 예. 명사, 빈칸",
    );
  });
});
