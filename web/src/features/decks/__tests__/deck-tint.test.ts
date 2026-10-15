// @vitest-environment node
import { describe, expect, it } from "vitest";

import { deckTintIndex } from "../deck-tint";
import type { DeckId } from "../library";

describe("deckTintIndex", () => {
  it("gives a deck the same tint as the app does, and spreads four decks over the four", () => {
    // app/test/deck/deck_tint_test.dart expects the same indexes for the same ids.
    const ids = [
      "00000000-0000-4000-8000-000000000001",
      "00000000-0000-4000-8000-000000000002",
      "00000000-0000-4000-8000-000000000003",
      "00000000-0000-4000-8000-000000000004",
    ] as DeckId[];

    expect(ids.map(deckTintIndex)).toEqual([1, 2, 3, 0]);
  });
});
