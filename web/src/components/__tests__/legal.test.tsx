import { screen } from "@testing-library/react";
import { describe, expect, it } from "vitest";

import { redirectTarget } from "@/testing/redirect";
import { render } from "@/testing/render";

import { ComingSoon } from "../coming-soon";
import { LegalLinks } from "../legal-links";

describe("the legal links", () => {
  it("open the pages that stand in for the documents while no URL is configured", async () => {
    await render(LegalLinks, {});

    expect(screen.getByRole("link", { name: "이용약관" })).toHaveAttribute("href", "/terms");
    expect(screen.getByRole("link", { name: "개인정보 처리방침" })).toHaveAttribute(
      "href",
      "/privacy",
    );
  });
});

describe("a legal document's page", () => {
  it("says the document is coming while it has no URL", async () => {
    await render(ComingSoon, { title: "이용약관", url: null });

    expect(screen.getByRole("heading", { name: "이용약관" })).toBeInTheDocument();
    expect(screen.getByText("아직 준비 중이에요. 곧 열어 드릴게요.")).toBeInTheDocument();
  });

  it("sends the visitor to the document once it has one", async () => {
    const url = "https://example.test/terms";

    expect(await redirectTarget(render(ComingSoon, { title: "이용약관", url }))).toBe(url);
  });
});
