import { render, screen } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { describe, expect, it } from "vitest";

import { testRouter } from "@/testing/router";

import { ReadFailure } from "../components/read-failure";

describe("a page's read failure", () => {
  it.each(["unreachable", "failed", "unreadable"] as const)(
    "offers 다시 시도 when %s, which reads the page again once per press",
    async (failure) => {
      render(<ReadFailure failure={failure} />);

      const alert = screen.getByRole("alert");
      expect(screen.queryByRole("link", { name: "로그인" })).not.toBeInTheDocument();
      expect(testRouter.refresh).not.toHaveBeenCalled();
      await userEvent.setup().click(screen.getByRole("button", { name: "다시 시도" }));
      expect(alert).toContainElement(screen.getByRole("button", { name: "다시 시도" }));
      expect(testRouter.refresh).toHaveBeenCalledOnce();
    },
  );

  it("offers 로그인 in place of 다시 시도 once the session ended", () => {
    render(<ReadFailure failure="rejected" />);

    expect(screen.getByRole("link", { name: "로그인" })).toHaveAttribute("href", "/login");
    expect(screen.queryByRole("button", { name: "다시 시도" })).not.toBeInTheDocument();
  });
});
