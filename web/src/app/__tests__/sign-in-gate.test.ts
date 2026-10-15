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

const publicRoutes = ["/login", "/auth/callback", "/api/health"];

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
  const url = `http://localhost:3000${pathname}`;
  const matched = unstable_doesMiddlewareMatch({
    config,
    url,
    cookies: Object.fromEntries(cookies.map(({ name, value }) => [name, value])),
  });
  if (!matched) return { matched, location: null };
  const request = new NextRequest(url, {
    headers: { cookie: cookies.map(({ name, value }) => `${name}=${value}`).join("; ") },
  });
  const response = await proxy(request);
  return { matched, location: response.headers.get("location") };
}

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

  it("lets a signed-out visitor open /login, /auth/callback and /api/health", async () => {
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
});
