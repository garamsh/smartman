/** The caller's identity from Supabase Auth, and the daily extraction count in `extraction_usage`. */

export const DAILY_EXTRACTION_LIMIT = 30;

/** A Supabase Auth user id. */
export type UserId = string & { readonly __brand: "UserId" };

export type SupabaseDeps = {
  readonly url: string;
  /** The service-role key; it bypasses row-level security, so it stays in the function. */
  readonly serviceRoleKey: string;
  readonly fetch: typeof fetch;
};

/** Raised when Supabase answers in a way the function does not expect; it maps to a 500. */
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

/** Records one extraction for the user and returns true, or false when today's limit is reached. */
export async function consumeExtraction(
  userId: UserId,
  deps: SupabaseDeps,
): Promise<boolean> {
  const response = await deps.fetch(
    `${deps.url}/rest/v1/rpc/consume_extraction`,
    {
      method: "POST",
      headers: {
        apikey: deps.serviceRoleKey,
        Authorization: `Bearer ${deps.serviceRoleKey}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({
        user_id: userId,
        daily_limit: DAILY_EXTRACTION_LIMIT,
      }),
    },
  );
  if (!response.ok) {
    throw new SupabaseError(`consume_extraction answered ${response.status}`);
  }
  const allowed: unknown = await response.json();
  if (typeof allowed !== "boolean") {
    throw new SupabaseError("consume_extraction answered no boolean");
  }
  return allowed;
}
