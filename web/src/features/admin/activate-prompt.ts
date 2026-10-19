"use server";

import { type ActionResult, refused } from "./action-call";
import { labelPrompt, isVersionId } from "./prompt-label";

/**
 * Serves prompt version [versionId] to every user, which is also how an earlier version is rolled
 * back to; activating the test version clears the test label. The server checks the role and
 * records it.
 */
export async function activatePrompt(versionId: number): Promise<ActionResult> {
  if (!isVersionId(versionId)) return refused("malformed");
  return labelPrompt("active", versionId, (changed) =>
    changed ? "이 버전을 모든 사용자에게 적용했어요." : "이미 사용 중인 버전이에요.",
  );
}
