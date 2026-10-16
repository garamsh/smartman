import { screen } from "@testing-library/react";
import { describe, expect, it } from "vitest";

import { render } from "@/testing/render";

import { LegalLinks } from "../legal-links";

describe("the legal links", () => {
  it("open each document's page on this app", async () => {
    await render(LegalLinks, {});

    expect(screen.getByRole("link", { name: "이용약관" })).toHaveAttribute("href", "/terms");
    expect(screen.getByRole("link", { name: "개인정보 처리방침" })).toHaveAttribute(
      "href",
      "/privacy",
    );
  });
});
