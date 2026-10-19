"use server";

import { revalidatePath } from "next/cache";

import { studyDayEnd, studyDayStart } from "@/features/study";
import { classifyFailure, requestTimeoutMs, type ServerFailure } from "@/supabase/failure";
import { createClient } from "@/supabase/server";

import { checkModel, type ModelCheck } from "./openrouter-models";
import { adminTimeZone } from "./read-admin";

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

/** What a plan's settings form shows after an attempt. */
export type PlanFormState = { message: string | null };

const modelMessages: Record<Exclude<ModelCheck, "usable">, string> = {
  unknown: "OpenRouter에 없는 모델이에요. 모델 ID를 확인해 주세요.",
  unsuitable: "사진과 구조화된 답을 함께 지원하지 않는 모델이에요.",
  unreachable: "OpenRouter에 연결할 수 없어 모델을 확인하지 못했어요. 잠시 후 다시 시도해 주세요.",
};

/**
 * Sets a plan's model and daily limit from the form's `plan`, `model` and `daily_limit`. The model
 * must be one OpenRouter lists with image input and structured outputs; the server checks the
 * role, the id's form and the limit's range, and records the change.
 */
export async function setPlan(_previous: PlanFormState, form: FormData): Promise<PlanFormState> {
  const plan = form.get("plan");
  const model = form.get("model");
  const limit = form.get("daily_limit");
  if (plan !== "free" && plan !== "pro" && plan !== "special") {
    return { message: failureMessages.malformed };
  }
  if (typeof model !== "string" || !/^[A-Za-z0-9_.-]+\/[A-Za-z0-9_.:-]+$/.test(model.trim())) {
    return { message: "모델 ID는 vendor/model 꼴로 적어 주세요." };
  }
  const dailyLimit = typeof limit === "string" && /^\d+$/.test(limit.trim()) ? Number(limit) : NaN;
  if (!Number.isInteger(dailyLimit) || dailyLimit > 1000) {
    return { message: "하루 한도는 0에서 1000 사이의 정수로 적어 주세요." };
  }
  const check = await checkModel(model.trim());
  if (check !== "usable") return { message: modelMessages[check] };
  const result = await call("admin_set_plan", {
    plan,
    model: model.trim(),
    daily_limit: dailyLimit,
  });
  if ("failure" in result) return { message: failureMessages[result.failure] };
  if (typeof result.data !== "boolean") return { message: failureMessages.unreadable };
  if (!result.data) return { message: "바뀐 것이 없어요." };
  revalidatePath("/admin", "layout");
  return { message: "저장했어요." };
}

/** What a user's plan form shows after an attempt. */
export type GrantPlanState = { message: string | null };

/**
 * Puts the form's `user` on its `plan`, Pro or Special, Special until the end of the study day of
 * `ends_on` in the admin's zone, or without an end when it is empty.
 */
export async function grantPlan(
  _previous: GrantPlanState,
  form: FormData,
): Promise<GrantPlanState> {
  const userId = form.get("user");
  const plan = form.get("plan");
  const endsOn = form.get("ends_on");
  if (!isUuid(userId) || (plan !== "pro" && plan !== "special")) {
    return { message: failureMessages.malformed };
  }
  let endsAt: string | null = null;
  if (typeof endsOn === "string" && endsOn !== "") {
    const date = /^(\d{4})-(\d{2})-(\d{2})$/.exec(endsOn);
    if (plan !== "special" || !date) return { message: "끝나는 날은 스페셜에만 정할 수 있어요." };
    const timeZone = await adminTimeZone();
    // Noon UTC falls on the same calendar date in every zone within 11 hours of UTC.
    const noon = Date.UTC(Number(date[1]), Number(date[2]) - 1, Number(date[3]), 12);
    endsAt = new Date(studyDayEnd(studyDayStart(noon, timeZone), timeZone)).toISOString();
  }
  const result = await call("admin_grant_plan", { user_id: userId, plan, ends_at: endsAt });
  if ("failure" in result) return { message: failureMessages[result.failure] };
  switch (result.data) {
    case "granted":
      revalidatePath("/admin", "layout");
      return { message: plan === "pro" ? "프로로 지정했어요." : "스페셜로 지정했어요." };
    case "bad_plan":
      return { message: "끝나는 날은 오늘 이후로 정해 주세요." };
    case "no_user":
      return { message: "없는 사용자예요." };
    default:
      return { message: failureMessages.unreadable };
  }
}

/** Puts a user back on Free. */
export async function revokePlan(userId: string): Promise<ActionResult> {
  if (!isUuid(userId)) return refused("malformed");
  const result = await call("admin_revoke_plan", { user_id: userId });
  if ("failure" in result) return refused(result.failure);
  if (typeof result.data !== "boolean") return refused("unreadable");
  if (result.data) revalidatePath("/admin", "layout");
  return {
    changed: result.data,
    message: result.data ? "무료로 되돌렸어요." : "이미 무료예요.",
  };
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
