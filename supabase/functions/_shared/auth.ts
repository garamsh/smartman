/** The caller's identity from Supabase Auth, shared by every function that acts for a user. */

/** A Supabase Auth user id. */
export type UserId = string & { readonly __brand: "UserId" };

export type SupabaseDeps = {
  readonly url: string;
  /** The service-role key; it bypasses row-level security, so it stays in the function. */
  readonly serviceRoleKey: string;
  readonly fetch: typeof fetch;
};

/** Raised when Supabase cannot be reached or answers in a way the function does not expect. */
export class SupabaseError extends Error {
  override name = "SupabaseError";
}

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

/**
 * The signed-in user the bearer token belongs to, or null for a missing or invalid token, the
 * anon key, or an anonymous sign-in.
 */
export async function authenticate(
  authorization: string | null,
  deps: SupabaseDeps,
): Promise<UserId | null> {
  const token = authorization?.match(/^Bearer (\S+)$/)?.[1];
  if (token === undefined) return null;
  const response = await deps.fetch(`${deps.url}/auth/v1/user`, {
    headers: { apikey: deps.serviceRoleKey, Authorization: `Bearer ${token}` },
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
  return user.id as UserId;
}
