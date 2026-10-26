// @vitest-environment node
import { describe, expect, it } from "vitest";

import { deckColor, deckColors, deckFill, deckTintIndex } from "../deck-tint";
import type { DeckId } from "../library";

const ids = [
  "00000000-0000-4000-8000-000000000001",
  "00000000-0000-4000-8000-000000000002",
  "00000000-0000-4000-8000-000000000003",
  "00000000-0000-4000-8000-000000000004",
  "00000000-0000-4000-8000-000000000005",
  "00000000-0000-4000-8000-000000000006",
] as DeckId[];

describe("a deck's colour", () => {
  it("is the palette in the app's order, each drawn with its theme token", () => {
    // DeckColor in app/lib/deck/src/model.dart, in its order.
    expect(deckColors).toEqual(["blue", "sky", "violet", "amber", "slate", "sand"]);
    expect(deckColors.map(deckFill)).toEqual([
      "bg-deck-blue",
      "bg-deck-sky",
      "bg-deck-violet",
      "bg-deck-amber",
      "bg-deck-slate",
      "bg-deck-sand",
    ]);
  });

  it("defaults to the one the app's deckTintIndex(id, 6) selects, so six decks spread over the six", () => {
    // Each id's UTF-16 code units sum to 1728 plus its last digit, modulo six.
    expect(ids.map(deckTintIndex)).toEqual([1, 2, 3, 4, 5, 0]);
    expect(ids.map((id) => deckColor({ id, name: "", public: false }))).toEqual([
      "sky",
      "violet",
      "amber",
      "slate",
      "sand",
      "blue",
    ]);
  });

  it("is the stored one when this version knows it, and the id's otherwise", () => {
    const [id] = ids;
    if (!id) throw new Error("the fixed ids are listed");
    expect(deckColor({ id, name: "", public: false, color: "amber" })).toBe("amber");
    // Control: the same deck with no key, and with keys this version does not know.
    expect(deckColor({ id, name: "", public: false })).toBe("sky");
    expect(deckColor({ id, name: "", public: false, color: "teal" })).toBe("sky");
    expect(deckColor({ id, name: "", public: false, color: "constructor" })).toBe("sky");
  });
});
