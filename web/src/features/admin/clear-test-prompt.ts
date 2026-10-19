"use server";

import { revalidatePath } from "next/cache";

import { type ActionResult, call, refused } from "./action-call";

/** Clears the test version, so admins are served the active one again. */
export async function clearTestPrompt(): Promise<ActionResult> {
  const result = await call("admin_clear_test_prompt", {});
  if ("failure" in result) return refused(result.failure);
  if (typeof result.data !== "boolean") return refused("unreadable");
  if (result.data) revalidatePath("/admin", "layout");
  return {
    changed: result.data,
    message: result.data
      ? "테스트를 끝냈어요. 관리자도 사용 중인 버전을 써요."
      : "테스트 중인 버전이 없어요.",
  };
}
