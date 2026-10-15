import { readFile } from "node:fs/promises";

import { http, HttpResponse } from "msw";

/** The Supabase project every test is configured with (vitest.config.ts). */
export const supabaseUrl = "http://supabase.test";

/** The user Supabase Auth knows and every test signs in as, unless it says otherwise. */
export const testUser = {
  id: "00000000-0000-4000-8000-000000000001",
  email: "learner@example.com",
};

/** A second user Supabase Auth knows, for tests of what one user may see of another's. */
export const otherUser = {
  id: "00000000-0000-4000-8000-000000000002",
  email: "other@example.com",
};

type User = typeof testUser;

function base64url(value: object) {
  return Buffer.from(JSON.stringify(value)).toString("base64url");
}

/** An HS256 access token for [user]; Supabase Auth, not the signature, decides it is valid. */
function accessToken(user: User): string {
  return [
    base64url({ alg: "HS256", typ: "JWT" }),
    base64url({
      sub: user.id,
      email: user.email,
      aud: "authenticated",
      role: "authenticated",
      exp: Math.floor(Date.now() / 1000) + 3600,
    }),
    Buffer.from("signature").toString("base64url"),
  ].join(".");
}

export const testAccessToken = accessToken(testUser);
export const otherAccessToken = accessToken(otherUser);

/** The user an `Authorization` header's token belongs to, or null for a token Auth refuses. */
export function bearerUser(authorization: string | null): User | null {
  if (authorization === `Bearer ${testAccessToken}`) return testUser;
  if (authorization === `Bearer ${otherAccessToken}`) return otherUser;
  return null;
}

/** What Supabase Auth answers for a session of [user]. */
const userBody = (user: User) => ({
  ...user,
  aud: "authenticated",
  role: "authenticated",
  app_metadata: { provider: "google" },
  user_metadata: {},
  created_at: "2026-10-15T00:00:00Z",
});

/** The code `/auth/callback` receives when [testUser] signed in at Google. */
export const testAuthCode = "auth-code";

/**
 * Supabase Auth: the user endpoint knows [testAccessToken] and [otherAccessToken] and refuses
 * any other token, the
 * PKCE token endpoint exchanges [testAuthCode] alone, and logout succeeds.
 */
export const handlers = [
  http.get(`${supabaseUrl}/auth/v1/user`, ({ request }) => {
    const user = bearerUser(request.headers.get("authorization"));
    if (!user) {
      return HttpResponse.json(
        { code: 403, error_code: "bad_jwt", msg: "invalid JWT" },
        { status: 403 },
      );
    }
    return HttpResponse.json(userBody(user));
  }),
  http.post(`${supabaseUrl}/auth/v1/token`, async ({ request }) => {
    const body: unknown = await request.json();
    const code = typeof body === "object" && body !== null && "auth_code" in body && body.auth_code;
    if (code !== testAuthCode) {
      return HttpResponse.json(
        { code: 400, error_code: "flow_state_not_found", msg: "invalid flow state" },
        { status: 400 },
      );
    }
    return HttpResponse.json({
      access_token: testAccessToken,
      refresh_token: "refresh-token",
      token_type: "bearer",
      expires_in: 3600,
      expires_at: Math.floor(Date.now() / 1000) + 3600,
      user: userBody(testUser),
    });
  }),
  http.post(`${supabaseUrl}/auth/v1/logout`, () => new HttpResponse(null, { status: 204 })),
];

/**
 * The app's own static files, as the browser fetches them: Vite names a file it serves by its
 * path on disk under `/@fs/`. Only the engine's `.wasm` is fetched this way.
 */
export const staticFiles = http.get("http://localhost:3000/@fs/*", async ({ request }) => {
  const file = decodeURIComponent(new URL(request.url).pathname.slice("/@fs".length));
  if (!file.endsWith(".wasm")) return new HttpResponse(null, { status: 404 });
  return new HttpResponse(await readFile(file), {
    headers: { "content-type": "application/wasm" },
  });
});

/** Supabase Auth unreachable: every request fails at the network. */
export const supabaseUnreachable = http.all(`${supabaseUrl}/*`, () => HttpResponse.error());
