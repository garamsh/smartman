import { render, screen } from "@testing-library/react";
import { describe, expect, it } from "vitest";

import { RetentionPreview } from "../components/retention-preview";

describe("the 오늘 page's retention card", () => {
  it("links to 기록 with a target at least the tap target high", () => {
    render(<RetentionPreview days={[]} timeZone="Asia/Seoul" />);

    const link = screen.getByRole("link", { name: "기록에서 자세히 보기" });
    expect(link).toHaveAttribute("href", "/record");
    expect(link.className.split(" ")).toContain("min-h-tap-target");
  });
});
