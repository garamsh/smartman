"use server";

import { revalidatePath } from "next/cache";

import { type ActionResult, call, isUuid, refused } from "./action-call";

/** Deletes a deck's reports. A hidden deck stays hidden. */
export async function dismissReports(deckId: string): Promise<ActionResult> {
  if (!isUuid(deckId)) return refused("malformed");
  const result = await call("admin_dismiss_reports", { deck_id: deckId });
  if ("failure" in result) return refused(result.failure);
  if (typeof result.data !== "number") return refused("unreadable");
  if (result.data === 0) return { changed: false, message: "정리할 신고가 없어요." };
  revalidatePath("/admin", "layout");
  return { changed: true, message: `신고 ${String(result.data)}건을 정리했어요.` };
}
