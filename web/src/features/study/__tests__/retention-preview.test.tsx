import { render, screen } from "@testing-library/react";
import { describe, expect, it } from "vitest";

import { chipTone } from "@/testing/chip";
import { start } from "@/testing/library";

import { RetentionPreview } from "../components/retention-preview";

describe("the 오늘 page's retention card", () => {
  it("links to 기록 with a target at least the tap target high", () => {
    render(<RetentionPreview days={[]} timeZone="Asia/Seoul" />);

    const link = screen.getByRole("link", { name: "기록에서 자세히 보기" });
    expect(link).toHaveAttribute("href", "/record");
    expect(link.className.split(" ")).toContain("min-h-tap-target");
  });

  it("states its gap in the one chip, amber below the target and the brand's tint at or above it", () => {
    const { unmount } = render(
      <RetentionPreview
        days={[{ dayStart: start, cards: 2, reviews: 2, known: 1 }]}
        timeZone="Asia/Seoul"
      />,
    );
    expect(chipTone(screen.getByText("목표보다 40% 낮아요"))).toBe("tint-amber");
    unmount();

    // Control: a share above the target takes the brand's tone, in the same chip.
    render(
      <RetentionPreview
        days={[{ dayStart: start, cards: 2, reviews: 2, known: 2 }]}
        timeZone="Asia/Seoul"
      />,
    );
    expect(chipTone(screen.getByText("목표보다 10% 높아요"))).toBe("brand-tint");
  });
});
