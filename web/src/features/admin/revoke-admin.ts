"use server";

import { revalidatePath } from "next/cache";

import { type ActionResult, call, isUuid, refused } from "./action-call";

/** Removes another admin's role; the server refuses the caller's own. */
export async function revokeAdmin(userId: string): Promise<ActionResult> {
  if (!isUuid(userId)) return refused("malformed");
  const result = await call("admin_revoke_admin", { user_id: userId });
  if ("failure" in result) return refused(result.failure);
  switch (result.data) {
    case "revoked":
      revalidatePath("/admin", "layout");
      return { changed: true, message: "관리자에서 해제했어요." };
    case "self":
      return { changed: false, message: "내 관리자 권한은 해제할 수 없어요." };
    case "not_admin":
      return { changed: false, message: "관리자가 아니에요." };
    default:
      return refused("unreadable");
  }
}
