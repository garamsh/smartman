// @vitest-environment node
import { NextRequest } from "next/server";
import { beforeEach, describe, expect, it, vi } from "vitest";

import { testAuthCode, testUser } from "@/testing/mocks/handlers";
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
});
