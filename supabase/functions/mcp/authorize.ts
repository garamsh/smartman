/** The caller of the MCP server: a user whose token the project's OAuth server issued to a client. */

import { SupabaseError, type UserId } from "../_shared/auth.ts";

/** The signed-in user and the token every read and write carries. */
export type Caller = { readonly userId: UserId; readonly token: string };

/** The claims of a JWT's payload, read without verifying it. */
function claims(token: string): Record<string, unknown> | null {
  const payload = token.split(".")[1];
  if (payload === undefined) return null;
  try {
    const json = atob(payload.replace(/-/g, "+").replace(/_/g, "/"));
    const bytes = Uint8Array.from(json, (char) => char.charCodeAt(0));
    const value: unknown = JSON.parse(new TextDecoder().decode(bytes));
    return typeof value === "object" && value !== null && !Array.isArray(value)
      ? value as Record<string, unknown>
      : null;
  } catch {
    return null;
  }
}

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

/**
 * The caller the bearer token belongs to, or null for a missing, invalid or expired token, an
 * anonymous sign-in, or a session the OAuth server did not issue: Supabase's tokens all carry
 * `aud: authenticated`, so the `client_id` claim is what marks a token issued to a connector
 * (ADR 0126). Supabase Auth verifies the token; its claims are trusted only after it accepts it.
 */
export async function authorize(
  authorization: string | null,
  deps: { url: string; anonKey: string; fetch: typeof fetch },
): Promise<Caller | null> {
  const token = authorization?.match(/^Bearer (\S+)$/i)?.[1];
  if (token === undefined) return null;
  const read = claims(token);
  if (
    read === null || typeof read.client_id !== "string" || read.client_id === ""
  ) return null;
  const response = await deps.fetch(`${deps.url}/auth/v1/user`, {
    headers: { apikey: deps.anonKey, Authorization: `Bearer ${token}` },
  }).catch((cause: unknown) => {
    throw new SupabaseError("auth could not be reached", { cause });
  });
  if (response.status === 401 || response.status === 403) {
    await response.body?.cancel();
    return null;
  }
  if (!response.ok) throw new SupabaseError(`auth answered ${response.status}`);
  const user: unknown = await response.json();
  if (typeof user !== "object" || user === null || !("id" in user)) {
    throw new SupabaseError("auth answered without a user");
  }
  if ("is_anonymous" in user && user.is_anonymous === true) return null;
  if (typeof user.id !== "string" || !UUID.test(user.id)) {
    throw new SupabaseError("auth answered without a user id");
  }
  if (user.id !== read.sub) return null;
  return { userId: user.id as UserId, token };
}
