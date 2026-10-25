import { screen, within } from "@testing-library/react";
import { beforeEach, describe, expect, it, vi } from "vitest";

import { FakePostgrest } from "@/testing/mocks/postgrest";
import { supabaseUnreachable, testUser } from "@/testing/mocks/handlers";
import { server } from "@/testing/mocks/server";
import { setRequestCookies } from "@/testing/next-headers";
import { redirectTarget } from "@/testing/redirect";
import { render } from "@/testing/render";
import { signedInCookies } from "@/testing/session";

import { AccountLink } from "../../_components/account-link";
import { Profile } from "../_components/profile";
import AccountPage from "../page";

vi.mock("next/headers", () => import("@/testing/next-headers"));

describe("the account page", () => {
  beforeEach(async () => {
    setRequestCookies(await signedInCookies());
    // The rows its 공부 section reads.
    server.use(...new FakePostgrest().handlers);
  });

  it("reads the session on the server and shows who is signed in, with sign-out", async () => {
    await render(Profile, {});

    expect(screen.getByRole("region", { name: "프로필" })).toHaveTextContent(
      `${testUser.email.charAt(0).toLocaleUpperCase()}${testUser.email}`,
    );
    expect(screen.getByRole("button", { name: "로그아웃" })).toBeEnabled();
  });

  it("says the server cannot be reached when Supabase does not answer", async () => {
    server.use(supabaseUnreachable);

    await render(Profile, {});

    expect(screen.getByRole("alert")).toHaveTextContent(
      "서버에 연결할 수 없어요. 연결을 확인하고 다시 시도해 주세요.",
    );
    // The next step, and the theme choice, which needs no server.
    expect(
      within(screen.getByRole("alert")).getByRole("button", { name: "다시 시도" }),
    ).toBeInTheDocument();
    expect(screen.getByRole("radiogroup", { name: "화면" })).toBeInTheDocument();
  });

  it("redirects to /login without a session", async () => {
    setRequestCookies([]);

    expect(await redirectTarget(render(Profile, {}))).toBe("/login");
  });

  it("links to the terms and the privacy policy at its foot", async () => {
    await render(AccountPage, {});

    const links = within(screen.getByRole("navigation", { name: "약관" }));
    expect(links.getByRole("link", { name: "이용약관" })).toHaveAttribute("href", "/terms");
    expect(links.getByRole("link", { name: "개인정보 처리방침" })).toHaveAttribute(
      "href",
      "/privacy",
    );
  });
});

describe("the shell's account link", () => {
  beforeEach(async () => {
    setRequestCookies(await signedInCookies());
  });

  it("is the signed-in account's initial, and opens the account page", async () => {
    await render(AccountLink, {});

    const link = screen.getByRole("link", { name: "계정과 설정" });
    expect(link).toHaveAttribute("href", "/account");
    expect(link).toHaveTextContent(testUser.email.charAt(0).toLocaleUpperCase());
  });

  it("in the side menu, names 계정과 설정 beside the initial", async () => {
    await render(AccountLink, { labelled: true });

    const link = screen.getByRole("link", { name: /계정과 설정$/ });
    expect(link).toHaveAttribute("href", "/account");
    expect(link).toHaveTextContent(`${testUser.email.charAt(0).toLocaleUpperCase()}계정과 설정`);
  });

  it("redirects to /login without a session", async () => {
    setRequestCookies([]);

    expect(await redirectTarget(render(AccountLink, {}))).toBe("/login");
  });
});
