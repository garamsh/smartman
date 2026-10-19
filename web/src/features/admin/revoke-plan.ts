"use server";

import { revalidatePath } from "next/cache";

import { type ActionResult, call, parseUserId, refused } from "./action-call";

/** Puts a user back on Free. */
export async function revokePlan(userId: string): Promise<ActionResult> {
  const id = parseUserId(userId);
  if (id === null) return refused("malformed");
  const result = await call("admin_revoke_plan", { user_id: id });
  if ("failure" in result) return refused(result.failure);
  if (typeof result.data !== "boolean") return refused("unreadable");
  if (result.data) revalidatePath("/admin", "layout");
  return {
    changed: result.data,
    message: result.data ? "무료로 되돌렸어요." : "이미 무료예요.",
  };
}
