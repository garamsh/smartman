import { http, HttpResponse } from "msw";
import { beforeEach, describe, expect, it, vi } from "vitest";

import { supabaseUnreachable, supabaseUrl } from "@/testing/mocks/handlers";
import { server } from "@/testing/mocks/server";
import { currentCookies, setRequestCookies } from "@/testing/next-headers";
import { redirectTarget } from "@/testing/redirect";
import { signedInCookies } from "@/testing/session";

import { signOut } from "../actions";

vi.mock("next/headers", () => import("@/testing/next-headers"));

const failure = { error: "로그아웃하지 못했어요. 연결을 확인하고 다시 시도해 주세요." };

describe("signOut", () => {
  beforeEach(async () => {
    setRequestCookies(await signedInCookies());
  });

  it("ends only this browser's session, clears its cookies and redirects to /login", async () => {
    const scopes: (string | null)[] = [];
    server.use(
      http.post(`${supabaseUrl}/auth/v1/logout`, ({ request }) => {
        scopes.push(new URL(request.url).searchParams.get("scope"));
        return new HttpResponse(null, { status: 204 });
      }),
    );
    expect(currentCookies()).not.toEqual([]);

    expect(await redirectTarget(signOut({ error: null }))).toBe("/login");

    expect(scopes).toEqual(["local"]);
    expect(currentCookies()).toEqual([]);
  });

  it("returns the reason when Supabase Auth cannot be reached, and succeeds when retried", async () => {
    server.use(supabaseUnreachable);

    expect(await signOut({ error: null })).toEqual(failure);
    expect(await redirectTarget(signOut({ error: null }))).toBe("/login");
    expect(currentCookies()).toEqual([]);
  });
});
