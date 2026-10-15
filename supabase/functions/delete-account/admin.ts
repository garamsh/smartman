/** Deleting a user through Supabase Auth's admin API. */

import {
  type SupabaseDeps,
  SupabaseError,
  type UserId,
} from "../_shared/auth.ts";

/**
 * Deletes the user for good, which deletes every row referencing it through `on delete cascade`.
 * Throws [SupabaseError] when Supabase Auth cannot be reached or does not delete the user.
 */
export async function deleteUser(
  userId: UserId,
  deps: SupabaseDeps,
): Promise<void> {
  const response = await deps.fetch(
    `${deps.url}/auth/v1/admin/users/${userId}`,
    {
      method: "DELETE",
      headers: {
        apikey: deps.serviceRoleKey,
        Authorization: `Bearer ${deps.serviceRoleKey}`,
      },
    },
  ).catch((cause: unknown) => {
    throw new SupabaseError("auth admin could not be reached", { cause });
  });
  await response.body?.cancel();
  if (!response.ok) {
    throw new SupabaseError(`auth admin answered ${response.status}`);
  }
}
