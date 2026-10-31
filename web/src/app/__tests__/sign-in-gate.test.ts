// @vitest-environment node
import { readdirSync } from "node:fs";
import path from "node:path";

import { unstable_doesMiddlewareMatch } from "next/experimental/testing/server";
import { NextRequest } from "next/server";
import { beforeAll, describe, expect, it } from "vitest";

import { config, proxy } from "@/proxy";
import { supabaseUnreachable } from "@/testing/mocks/handlers";
import { server } from "@/testing/mocks/server";
import { signedInCookies } from "@/testing/session";

const publicRoutes = ["/login", "/auth/callback", "/terms", "/privacy", "/api/health"];

/** Every URL the app routes: one per page.tsx or route.ts under src/app. */
function appRoutes(): string[] {
  const appDir = path.join(import.meta.dirname, "..");
  return readdirSync(appDir, { recursive: true, encoding: "utf8" })
    .map((file) => file.split(path.sep))
    .filter((parts) => /^(page\.tsx|route\.ts)$/.test(parts.at(-1) ?? ""))
    .filter((parts) => !parts.some((part) => part.startsWith("_")))
    .map(
      (parts) =>
        "/" +
        parts
          .slice(0, -1)
          .filter((part) => !/^\(.*\)$/.test(part))
          .join("/"),
    );
}

type Cookie = { name: string; value: string };

/** What a request for [pathname] meets: whether the proxy runs, and where it redirects. */
async function visit(pathname: string, cookies: Cookie[] = []) {
  const { matched, response } = await respond(pathname, cookies);
  return { matched, location: response?.headers.get("location") ?? null };
}

/** The proxy's whole response to a request for [pathname], or null where it does not run. */
async function respond(pathname: string, cookies: Cookie[] = []) {
  const url = `http://localhost:3000${pathname}`;
  const matched = unstable_doesMiddlewareMatch({
    config,
    url,
    cookies: Object.fromEntries(cookies.map(({ name, value }) => [name, value])),
  });
  if (!matched) return { matched, response: null };
  const request = new NextRequest(url, {
    headers: { cookie: cookies.map(({ name, value }) => `${name}=${value}`).join("; ") },
  });
  return { matched, response: await proxy(request) };
}

/** The cookie the proxy keeps an AI app's consent in across sign-in. */
const consentCookie = "smartman-oauth-consent";

const routes = appRoutes();
const gatedRoutes = [...routes.filter((route) => !publicRoutes.includes(route)), "/no-such-page"];

describe("the sign-in gate", () => {
  let signedIn: Cookie[];
  beforeAll(async () => {
    signedIn = await signedInCookies();
  });

  it("finds every route the app serves", () => {
    expect(routes).toEqual(expect.arrayContaining(["/", ...publicRoutes]));
  });

  it("sends a signed-out visitor from every other route to /login", async () => {
    for (const route of gatedRoutes) {
      expect(await visit(route), route).toEqual({
        matched: true,
        location: "http://localhost:3000/login",
      });
    }
  });

  it("lets a signed-out visitor open /login, /auth/callback, the legal pages and /api/health", async () => {
    for (const route of publicRoutes) {
      expect((await visit(route)).location, route).toBeNull();
    }
  });

  it("lets a signed-in visitor open every route", async () => {
    for (const route of gatedRoutes) {
      expect((await visit(route, signedIn)).location, route).toBeNull();
    }
  });

  it("sends a visitor whose session Supabase rejects to /login", async () => {
    const rejected = signedIn.map(({ name }) => ({ name, value: "base64-e30" }));
    expect((await visit("/", rejected)).location).toBe("http://localhost:3000/login");
  });

  it("keeps a signed-in visitor on the page while Supabase is unreachable", async () => {
    server.use(supabaseUnreachable);
    expect((await visit("/", signedIn)).location).toBeNull();
  });

  it("keeps the consent a signed-out visitor was sent from to /login, and opens it once sign-in lands on /", async () => {
    const { response: out } = await respond("/oauth/consent?authorization_id=abc_123-XYZ");
    expect(out?.headers.get("location")).toBe("http://localhost:3000/login");
    expect(out?.cookies.get(consentCookie)).toMatchObject({
      value: "abc_123-XYZ",
      httpOnly: true,
      sameSite: "lax",
      maxAge: 600,
    });

    const { response: back } = await respond("/", [
      ...signedIn,
      { name: consentCookie, value: "abc_123-XYZ" },
    ]);
    expect(back?.headers.get("location")).toBe(
      "http://localhost:3000/oauth/consent?authorization_id=abc_123-XYZ",
    );
    expect(back?.cookies.get(consentCookie)?.value).toBe("");
    // Control: without the cookie, a signed-in visitor stays on /.
    expect((await visit("/", signedIn)).location).toBeNull();
  });

  it("keeps no consent for a malformed id, and drops a malformed cookie without leaving /", async () => {
    const { response: out } = await respond("/oauth/consent?authorization_id=..%2Fadmin");
    expect(out?.headers.get("location")).toBe("http://localhost:3000/login");
    expect(out?.cookies.get(consentCookie)).toBeUndefined();

    const { response: back } = await respond("/", [
      ...signedIn,
      { name: consentCookie, value: "../admin" },
    ]);
    expect(back?.headers.get("location")).toBeNull();
    expect(back?.cookies.get(consentCookie)?.value).toBe("");
  });

  it("opens a kept consent from / alone, not from another page", async () => {
    const { response } = await respond("/decks", [
      ...signedIn,
      { name: consentCookie, value: "abc_123-XYZ" },
    ]);
    expect(response?.headers.get("location")).toBeNull();
  });
});
