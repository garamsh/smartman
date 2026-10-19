"use server";

import { revalidatePath } from "next/cache";

import { type ActionResult, call, isUuid, refused } from "./action-call";

/** Lifts a user's suspension, so the user signs in again; the data was kept. */
export async function unsuspendUser(userId: string): Promise<ActionResult> {
  if (!isUuid(userId)) return refused("malformed");
  const result = await call("admin_unsuspend_user", { user_id: userId });
  if ("failure" in result) return refused(result.failure);
  if (typeof result.data !== "boolean") return refused("unreadable");
  if (result.data) revalidatePath("/admin", "layout");
  return {
    changed: result.data,
    message: result.data ? "정지를 풀었어요." : "정지된 사용자가 아니에요.",
  };
}
