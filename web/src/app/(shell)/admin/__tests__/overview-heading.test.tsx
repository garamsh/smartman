import { render, screen } from "@testing-library/react";
import { describe, expect, it, vi } from "vitest";

import Page from "../page";

// The overview's content reads the server; only the page's own heading is under test here.
vi.mock("../_components/content", () => ({ OverviewContent: () => null }));

describe("the admin overview", () => {
  it("is headed 개요, the name the section menu gives it", () => {
    render(<Page />);

    expect(screen.getByRole("heading", { level: 1 })).toHaveAccessibleName("개요");
  });
});
