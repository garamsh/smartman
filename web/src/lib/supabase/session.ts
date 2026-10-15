import { isAuthRetryableFetchError, type SupabaseClient } from "@supabase/supabase-js";

/** Who the request is signed in as, or why that is not known. */
export type Session =
  { kind: "signed-in"; email: string } | { kind: "signed-out" } | { kind: "unreachable" };

/**
 * Reads the session from [client]'s cookies and verifies it with Supabase Auth. A session
 * Supabase rejects is signed out; a failure to reach Supabase is `unreachable`, so an outage
 * does not sign anyone out.
 */
export async function readSession(client: SupabaseClient): Promise<Session> {
  const { data, error } = await client.auth.getClaims();
  if (error && isAuthRetryableFetchError(error)) return { kind: "unreachable" };
  if (!data) return { kind: "signed-out" };
  const email = data.claims.email;
  return { kind: "signed-in", email: typeof email === "string" ? email : "" };
}

/**
 * The id of the user [client]'s session belongs to, verified with Supabase Auth: `rejected`
 * without a session Supabase accepts, `unreachable` when Supabase cannot be reached.
 */
export async function readUserId(
  client: SupabaseClient,
): Promise<{ userId: string } | { failure: "rejected" | "unreachable" }> {
  const { data, error } = await client.auth.getClaims();
  if (error && isAuthRetryableFetchError(error)) return { failure: "unreachable" };
  const userId = data?.claims.sub;
  return userId ? { userId } : { failure: "rejected" };
}
