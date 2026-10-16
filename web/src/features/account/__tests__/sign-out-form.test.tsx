import { render, screen } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { beforeEach, describe, expect, it, vi } from "vitest";

import { SignOutForm } from "../components/sign-out-form";

const failure = "로그아웃하지 못했어요. 연결을 확인하고 다시 시도해 주세요.";

const signOut = vi.fn<() => Promise<{ error: string | null }>>();

vi.mock("../actions", () => ({ signOut: () => signOut() }));

describe("SignOutForm", () => {
  beforeEach(() => {
    signOut.mockReset();
  });

  it("shows the reason beneath the button when sign-out fails", async () => {
    signOut.mockResolvedValue({ error: failure });
    render(<SignOutForm />);
    expect(screen.queryByRole("alert")).not.toBeInTheDocument();

    await userEvent.click(screen.getByRole("button", { name: "로그아웃" }));

    expect(await screen.findByRole("alert")).toHaveTextContent(failure);
  });

  it("shows progress in the button, which cannot be pressed again, while sign-out runs", async () => {
    signOut.mockReturnValue(new Promise(() => undefined));
    render(<SignOutForm />);
    const button = screen.getByRole("button", { name: "로그아웃" });
    // Control: before the press it is ready.
    expect(button).toBeEnabled();
    expect(button).toHaveAttribute("aria-busy", "false");

    await userEvent.click(button);

    expect(button).toBeDisabled();
    expect(button).toHaveAttribute("aria-busy", "true");
    await userEvent.click(button);
    expect(signOut).toHaveBeenCalledTimes(1);
  });
});
