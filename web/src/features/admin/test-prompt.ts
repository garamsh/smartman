"use server";

import { type ActionResult, refused } from "./action-call";
import { labelPrompt, isVersionId } from "./prompt-label";

/** Serves prompt version [versionId] to admins only, as the test version. */
export async function testPrompt(versionId: number): Promise<ActionResult> {
  if (!isVersionId(versionId)) return refused("malformed");
  return labelPrompt("test", versionId, (changed) =>
    changed ? "관리자에게만 이 버전을 쓰도록 했어요." : "이미 테스트 중인 버전이에요.",
  );
}
