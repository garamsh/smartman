import { AuthError } from "@supabase/supabase-js";
import { render, screen } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { beforeEach, describe, expect, it, vi } from "vitest";

import { SignInButton } from "../components/sign-in-button";

const signInWithOAuth = vi.fn();

vi.mock("@/lib/supabase/browser", () => ({
  createClient: () => ({ auth: { signInWithOAuth } }),
}));

const failure = "로그인을 시작하지 못했어요. 다시 시도해 주세요.";

describe("SignInButton", () => {
  beforeEach(() => {
    signInWithOAuth.mockReset();
  });

  it("starts Google sign-in back to this origin's /auth/callback, showing no error", async () => {
    signInWithOAuth.mockResolvedValue({ data: {}, error: null });
    render(<SignInButton />);

    await userEvent.click(screen.getByRole("button", { name: "Google로 로그인" }));

    expect(signInWithOAuth).toHaveBeenCalledWith({
      provider: "google",
      options: { redirectTo: `${window.location.origin}/auth/callback` },
    });
    expect(screen.queryByRole("alert")).not.toBeInTheDocument();
  });

  it("is Google's button: the light and the dark theme's G mark before the label", () => {
    render(<SignInButton />);

    const button = screen.getByRole("button", { name: "Google로 로그인" });
    // The marks are decorative, so the label alone names the button; they are found by source.
    const marks = Array.from(button.querySelectorAll("img"), (img) => ({
      src: img.getAttribute("src"),
      alt: img.getAttribute("alt"),
    }));
    expect(marks).toEqual([
      { src: "/google/g-mark-light.png", alt: "" },
      { src: "/google/g-mark-dark.png", alt: "" },
    ]);
    expect(button.lastChild).toHaveTextContent("Google로 로그인");
  });

  it("shows progress in the button, which cannot be pressed twice, while sign-in starts", async () => {
    signInWithOAuth.mockReturnValue(new Promise(() => undefined));
    render(<SignInButton />);

    await userEvent.click(screen.getByRole("button", { name: "Google로 로그인" }));

    const button = screen.getByRole("button", { name: "Google로 로그인" });
    expect(button).toBeDisabled();
    expect(button).toHaveAttribute("aria-busy", "true");
    // Progress takes the mark's place inside the pressed button.
    expect(button.querySelector("img")).toBeNull();
    expect(button.querySelector("svg")).not.toBeNull();
    await userEvent.click(button);
    expect(signInWithOAuth).toHaveBeenCalledTimes(1);
  });

  it("shows the reason when Supabase returns an error", async () => {
    signInWithOAuth.mockResolvedValue({ data: {}, error: new AuthError("no provider") });
    render(<SignInButton />);

    await userEvent.click(screen.getByRole("button", { name: "Google로 로그인" }));

    expect(await screen.findByRole("alert")).toHaveTextContent(failure);
    expect(screen.getByRole("button", { name: "Google로 로그인" })).toBeEnabled();
  });

  it("shows the reason when starting sign-in throws", async () => {
    signInWithOAuth.mockRejectedValue(new Error("storage unavailable"));
    render(<SignInButton />);

    await userEvent.click(screen.getByRole("button", { name: "Google로 로그인" }));

    expect(await screen.findByRole("alert")).toHaveTextContent(failure);
  });
});
