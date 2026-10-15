import { http, HttpResponse } from "msw";

/** The Supabase project every test is configured with (vitest.config.ts). */
export const supabaseUrl = "http://supabase.test";

/** The one user Supabase Auth knows, and the access token it accepts for them. */
export const testUser = {
  id: "00000000-0000-4000-8000-000000000001",
  email: "learner@example.com",
};

function base64url(value: object) {
  return Buffer.from(JSON.stringify(value)).toString("base64url");
}

/** An HS256 access token for [testUser]; Supabase Auth, not the signature, decides it is valid. */
export const testAccessToken = [
  base64url({ alg: "HS256", typ: "JWT" }),
  base64url({
    sub: testUser.id,
    email: testUser.email,
    aud: "authenticated",
    role: "authenticated",
    exp: Math.floor(Date.now() / 1000) + 3600,
  }),
  Buffer.from("signature").toString("base64url"),
].join(".");

/** What Supabase Auth answers for a session of [testUser]. */
const userBody = {
  ...testUser,
  aud: "authenticated",
  role: "authenticated",
  app_metadata: { provider: "google" },
  user_metadata: {},
  created_at: "2026-10-15T00:00:00Z",
};

/** The code `/auth/callback` receives when [testUser] signed in at Google. */
export const testAuthCode = "auth-code";

/**
 * Supabase Auth: the user endpoint knows [testAccessToken] and refuses any other token, the
 * PKCE token endpoint exchanges [testAuthCode] alone, and logout succeeds.
 */
export const handlers = [
  http.get(`${supabaseUrl}/auth/v1/user`, ({ request }) => {
    if (request.headers.get("authorization") !== `Bearer ${testAccessToken}`) {
      return HttpResponse.json(
        { code: 403, error_code: "bad_jwt", msg: "invalid JWT" },
        { status: 403 },
      );
    }
    return HttpResponse.json(userBody);
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
      user: userBody,
    });
  }),
  http.post(`${supabaseUrl}/auth/v1/logout`, () => new HttpResponse(null, { status: 204 })),
];

/** Supabase Auth unreachable: every request fails at the network. */
export const supabaseUnreachable = http.all(`${supabaseUrl}/*`, () => HttpResponse.error());
