"use server";

import { revalidatePath } from "next/cache";

import { type ActionResult, call, isUuid, refused } from "./action-call";

/**
 * Suspends a user with a reason: Supabase Auth then refuses the user's sign-in and refresh, and the
 * server its extractions and sync writes (ADR 0072). The server checks the role and records it.
 */
export async function suspendUser(userId: string, reason: string): Promise<ActionResult> {
  if (!isUuid(userId) || typeof reason !== "string") return refused("malformed");
  if (reason.trim() === "" || reason.trim().length > 500) {
    return { changed: false, message: "정지하는 이유를 500자 안으로 적어 주세요." };
  }
  const result = await call("admin_suspend_user", { user_id: userId, reason: reason.trim() });
  if ("failure" in result) return refused(result.failure);
  switch (result.data) {
    case "suspended":
      revalidatePath("/admin", "layout");
      return { changed: true, message: "이용을 정지했어요." };
    case "already":
      return { changed: false, message: "이미 정지된 사용자예요." };
    case "self":
      return { changed: false, message: "내 계정은 정지할 수 없어요." };
    case "no_user":
      return { changed: false, message: "없는 사용자예요." };
    default:
      return refused("unreadable");
  }
}
