import { render, screen } from "@testing-library/react";
import { describe, expect, it } from "vitest";

import { chipTone } from "@/testing/chip";

import { GradeChip } from "../components/graded-card";

describe("a grade's chip", () => {
  it("draws 안다 and 모른다 in the one chip, each in its grade's tone, hidden from screen readers", () => {
    render(
      <>
        <GradeChip answer="know" />
        <GradeChip answer="dontKnow" />
      </>,
    );

    expect(chipTone(screen.getByText("안다"))).toBe("know");
    expect(chipTone(screen.getByText("모른다"))).toBe("dont-know-text");
    expect(screen.getByText("안다").closest("[aria-hidden]")).not.toBeNull();
  });
});
