import { render, screen } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { describe, expect, it, vi } from "vitest";

import { SignOutForm } from "../components/sign-out-form";

const failure = "로그아웃하지 못했어요. 연결을 확인하고 다시 시도해 주세요.";

vi.mock("../actions", () => ({ signOut: () => Promise.resolve({ error: failure }) }));

describe("SignOutForm", () => {
  it("shows the reason beneath the button when sign-out fails", async () => {
    render(<SignOutForm />);
    expect(screen.queryByRole("alert")).not.toBeInTheDocument();

    await userEvent.click(screen.getByRole("button", { name: "로그아웃" }));

    expect(await screen.findByRole("alert")).toHaveTextContent(failure);
  });
});
