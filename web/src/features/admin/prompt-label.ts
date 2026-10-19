import "server-only";

import { revalidatePath } from "next/cache";

import { type ActionResult, call, refused } from "./action-call";

/** Whether [value], which crossed the network, is a prompt version's id. */
export function isVersionId(value: unknown): value is number {
  return typeof value === "number" && Number.isSafeInteger(value) && value > 0;
}

/** Points [label] at [versionId] through the server, and returns [message]'s sentence for it. */
export async function labelPrompt(
  label: "active" | "test",
  versionId: number,
  message: (changed: boolean) => string,
): Promise<ActionResult> {
  const result = await call("admin_set_prompt_label", { label, version_id: versionId });
  if ("failure" in result) return refused(result.failure);
  if (typeof result.data !== "boolean") return refused("unreadable");
  if (result.data) revalidatePath("/admin", "layout");
  return { changed: result.data, message: message(result.data) };
}
