import { render, screen } from "@testing-library/react";
import { describe, expect, it } from "vitest";

import { DeckList, parseDeckId } from "@/features/decks";
import { GradeChip } from "@/features/study/components/graded-card";
import { RetentionPreview } from "@/features/study/components/retention-preview";
import { chipTone } from "@/testing/chip";
import { start, uuidOf } from "@/testing/library";

import { Chip } from "../chip";

describe("the one chip", () => {
  it.each([
    ["neutral", ["bg-surface", "border-outline", "text-ink"]],
    ["brand", ["bg-brand-tint", "border-brand-tint", "text-ink"]],
    ["amber", ["bg-tint-amber", "border-tint-amber", "text-ink"]],
    ["know", ["bg-know", "border-know", "text-on-know"]],
    ["dontKnow", ["bg-dont-know-text", "border-dont-know-text", "text-on-dont-know-text"]],
  ] as const)(
    "draws the %s tone in the phone's fill, line and text, on the chip radius in the section type",
    (tone, colours) => {
      render(<Chip tone={tone}>words</Chip>);

      const chip = screen.getByText("words");
      expect(chip.className.split(" ")).toEqual(
        expect.arrayContaining([
          "rounded-chip",
          "text-section",
          "px-2",
          "py-1",
          "border",
          ...colours,
        ]),
      );
    },
  );

  it("puts a leading mark before its words", () => {
    render(<Chip leading={<svg data-testid="mark" />}>1일 연속</Chip>);

    const chip = screen.getByText("1일 연속");
    expect(chip.firstElementChild).toBe(screen.getByTestId("mark"));
  });

  it("draws the deck row's 공개 and today's count, a grade and the retention gap", () => {
    const deckId = parseDeckId(uuidOf("d-fr"));
    if (deckId === null) throw new Error("d-fr is no uuid");
    render(
      <>
        <DeckList
          rows={[
            {
              deck: { id: deckId, name: "French", public: true },
              cards: 2,
              today: 2,
              mastered: 0,
              learning: 0,
            },
          ]}
        />
        <GradeChip answer="know" />
        <GradeChip answer="dontKnow" />
        <RetentionPreview
          days={[{ dayStart: start, cards: 2, reviews: 2, known: 1 }]}
          timeZone="Asia/Seoul"
        />
      </>,
    );

    expect(chipTone(screen.getByText("공개"))).toBe("surface");
    expect(chipTone(screen.getByText("오늘 2"))).toBe("brand-tint");
    expect(chipTone(screen.getByText("안다"))).toBe("know");
    expect(chipTone(screen.getByText("모른다"))).toBe("dont-know-text");
    expect(chipTone(screen.getByText("목표보다 40%p 낮아요"))).toBe("tint-amber");
    // Control: the deck's name beside the chips is drawn by none.
    expect(chipTone(screen.getByText("French"))).toBeNull();
  });
});
