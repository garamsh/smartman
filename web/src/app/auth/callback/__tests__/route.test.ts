// @vitest-environment node
import { http, HttpResponse } from "msw";
import { NextRequest } from "next/server";
import { beforeEach, describe, expect, it, vi } from "vitest";

import { supabaseUrl, testAuthCode, testUser } from "@/testing/mocks/handlers";
import { server } from "@/testing/mocks/server";
import { setRequestCookies } from "@/testing/next-headers";
import { signInStartedCookies } from "@/testing/session";
import { createClient } from "@/supabase/server";
import { readSession } from "@/supabase/session";

import { GET } from "../route";

vi.mock("next/headers", () => import("@/testing/next-headers"));

function callback(query: string) {
  return GET(new NextRequest(`http://localhost:3000/auth/callback${query}`));
}

describe("GET /auth/callback", () => {
  beforeEach(async () => {
    setRequestCookies(await signInStartedCookies());
  });

  it("exchanges the code for a session and opens the app", async () => {
    const response = await callback(`?code=${testAuthCode}`);

    expect(response.headers.get("location")).toBe("http://localhost:3000/");
    expect(await readSession(await createClient())).toEqual({
      kind: "signed-in",
      email: testUser.email,
    });
  });

  it("opens /login with error=failed when Supabase refuses the code", async () => {
    const response = await callback("?code=stale-code");

    expect(response.headers.get("location")).toBe("http://localhost:3000/login?error=failed");
    expect(await readSession(await createClient())).toEqual({ kind: "signed-out" });
  });

  it("opens /login with error=failed when Supabase sends another error instead of a code", async () => {
    const response = await callback("?error=server_error");

    expect(response.headers.get("location")).toBe("http://localhost:3000/login?error=failed");
  });

  it("opens /login with error=cancelled when the user cancelled at Google", async () => {
    const response = await callback("?error=access_denied");

    expect(response.headers.get("location")).toBe("http://localhost:3000/login?error=cancelled");
  });

  it("opens /login with error=suspended when Supabase refuses a suspended account, by its redirect or its code exchange", async () => {
    const redirected = await callback("?error=access_denied&error_code=user_banned");
    expect(redirected.headers.get("location")).toBe("http://localhost:3000/login?error=suspended");

    server.use(
      http.post(`${supabaseUrl}/auth/v1/token`, () =>
        HttpResponse.json(
          { code: 400, error_code: "user_banned", msg: "User is banned" },
          { status: 400 },
        ),
      ),
    );
    const exchanged = await callback(`?code=${testAuthCode}`);
    expect(exchanged.headers.get("location")).toBe("http://localhost:3000/login?error=suspended");
    expect(await readSession(await createClient())).toEqual({ kind: "signed-out" });
  });
});
