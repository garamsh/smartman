import { render, screen } from "@testing-library/react";
import { describe, expect, it } from "vitest";

import { uuidOf } from "@/testing/library";

import { DeckList } from "../components/deck-list";
import { parseDeckId } from "../library";

describe("a deck row's progress bar", () => {
  it("draws mastered in ink and learning in ink at 45%, with no gap between the shares, as the phone does", () => {
    const id = parseDeckId(uuidOf("d-fr"));
    if (!id) throw new Error("the fixed id is a uuid");
    render(
      <DeckList
        rows={[
          {
            deck: { id, name: "French", public: false },
            cards: 4,
            today: 0,
            mastered: 1,
            learning: 2,
          },
        ]}
      />,
    );

    const row = screen.getByRole("link", { name: /^French/ });
    const share = (width: string) =>
      Array.from(row.querySelectorAll<HTMLElement>("span[style]")).find(
        (span) => span.style.width === width,
      );
    const mastered = share("25%");
    const learning = share("50%");
    expect(mastered?.className.split(" ")).toEqual(["bg-ink"]);
    expect(learning?.className.split(" ")).toEqual(["bg-ink/45"]);
    // The two shares sit side by side in one track, with nothing between them.
    expect(learning?.parentElement).toBe(mastered?.parentElement);
    expect(learning?.parentElement?.className.split(" ")).not.toEqual(
      expect.arrayContaining([expect.stringMatching(/^gap-/)]),
    );
  });
});
