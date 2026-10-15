import { screen } from "@testing-library/react";
import { beforeEach, describe, expect, it, vi } from "vitest";

import { supabaseUnreachable, testUser } from "@/testing/mocks/handlers";
import { server } from "@/testing/mocks/server";
import { setRequestCookies } from "@/testing/next-headers";
import { redirectTarget } from "@/testing/redirect";
import { render } from "@/testing/render";
import { signedInCookies } from "@/testing/session";

import { Account } from "../_components/account";

vi.mock("next/headers", () => import("@/testing/next-headers"));

describe("the home page's account section", () => {
  beforeEach(async () => {
    setRequestCookies(await signedInCookies());
  });

  it("reads the session on the server and shows who is signed in", async () => {
    await render(Account, {});

    expect(screen.getByText(`${testUser.email}(으)로 로그인했어요.`)).toBeInTheDocument();
    expect(screen.getByRole("button", { name: "로그아웃" })).toBeEnabled();
  });

  it("says the server cannot be reached when Supabase does not answer", async () => {
    server.use(supabaseUnreachable);

    await render(Account, {});

    expect(screen.getByRole("alert")).toHaveTextContent(
      "서버에 연결할 수 없어요. 연결을 확인하고 다시 시도해 주세요.",
    );
  });

  it("redirects to /login without a session", async () => {
    setRequestCookies([]);

    expect(await redirectTarget(render(Account, {}))).toBe("/login");
  });
});
