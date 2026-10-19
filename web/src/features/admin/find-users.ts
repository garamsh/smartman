"use server";

import { failureMessages } from "./action-call";
import { searchUsers, type UserPage } from "./read-admin";

/**
 * The [page]th page of the users whose email holds [query], for the users page's search as the
 * admin types; the server checks the role. A blank query finds no one without asking.
 */
export async function findUsers(
  query: string,
  page: number,
): Promise<UserPage | { message: string }> {
  // The arguments crossed the network, whatever their declared types.
  if (typeof query !== "string" || !Number.isInteger(page) || page < 0) {
    return { message: failureMessages.malformed };
  }
  if (query.trim() === "") return { users: [], total: 0 };
  const read = await searchUsers(query.trim(), page);
  return "failure" in read ? { message: failureMessages[read.failure] } : read.data;
}
