"use server";

import { revalidatePath } from "next/cache";

import { classifyFailure, requestTimeoutMs, type ServerFailure } from "@/supabase/failure";
import { createClient } from "@/supabase/server";

/** What an admin action shows when it returns: whether it changed something, and the sentence. */
export type ActionResult = { changed: boolean; message: string };

const failureMessages: Record<ServerFailure | "unreadable" | "malformed", string> = {
  rejected: "관리자만 할 수 있어요.",
  unreachable: "서버에 연결할 수 없어요. 연결을 확인하고 다시 시도해 주세요.",
  failed: "하지 못했어요. 잠시 후 다시 시도해 주세요.",
  unreadable: "하지 못했어요. 잠시 후 다시 시도해 주세요.",
  malformed: "하지 못했어요. 잠시 후 다시 시도해 주세요.",
};

const uuid = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/;

/** Hides a deck from the public listing; the server checks the caller's role and records it. */
export async function hideDeck(deckId: string): Promise<ActionResult> {
  return deckAction("admin_set_deck_hidden", deckId, { hidden: true }, (changed) =>
    changed ? "덱을 숨겼어요." : "이미 숨겨진 덱이에요.",
  );
}

/** Shows a hidden deck in the public listing again. */
export async function unhideDeck(deckId: string): Promise<ActionResult> {
  return deckAction("admin_set_deck_hidden", deckId, { hidden: false }, (changed) =>
    changed ? "숨김을 풀었어요." : "숨겨지지 않은 덱이에요.",
  );
}

/** Makes a public deck private; the owner's devices pull the change. */
export async function unpublishDeck(deckId: string): Promise<ActionResult> {
  return deckAction("admin_unpublish_deck", deckId, {}, (changed) =>
    changed ? "비공개로 바꿨어요." : "이미 비공개인 덱이에요.",
  );
}

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

/** What the grant form shows after an attempt. */
export type GrantState = { message: string | null };

/** Makes the existing user with the form's `email` an admin. */
export async function grantAdmin(_previous: GrantState, form: FormData): Promise<GrantState> {
  const email = form.get("email");
  if (typeof email !== "string" || email.trim() === "") {
    return { message: "이메일을 입력해 주세요." };
  }
  const result = await call("admin_grant_admin", { email: email.trim() });
  if ("failure" in result) return { message: failureMessages[result.failure] };
  switch (result.data) {
    case "granted":
      revalidatePath("/admin", "layout");
      return { message: `${email.trim()}님을 관리자로 지정했어요.` };
    case "already":
      return { message: "이미 관리자예요." };
    case "no_user":
      return { message: "이 이메일로 가입한 사용자가 없어요." };
    default:
      return { message: failureMessages.unreadable };
  }
}

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

async function deckAction(
  name: string,
  deckId: string,
  args: Record<string, unknown>,
  message: (changed: boolean) => string,
): Promise<ActionResult> {
  // The argument crossed the network, whatever its declared type.
  if (!isUuid(deckId)) return refused("malformed");
  const result = await call(name, { deck_id: deckId, ...args });
  if ("failure" in result) return refused(result.failure);
  if (typeof result.data !== "boolean") return refused("unreadable");
  if (result.data) revalidatePath("/admin", "layout");
  return { changed: result.data, message: message(result.data) };
}

async function call(
  name: string,
  args: Record<string, unknown>,
): Promise<{ data: unknown } | { failure: ServerFailure }> {
  const supabase = await createClient();
  const result = await supabase.rpc(name, args).abortSignal(AbortSignal.timeout(requestTimeoutMs));
  if (result.error) return { failure: classifyFailure(result.error, result.status) };
  const data: unknown = result.data;
  return { data };
}

function refused(failure: keyof typeof failureMessages): ActionResult {
  return { changed: false, message: failureMessages[failure] };
}

function isUuid(value: unknown): value is string {
  return typeof value === "string" && uuid.test(value);
}
