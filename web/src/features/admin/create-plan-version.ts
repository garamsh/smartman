"use server";

import { revalidatePath } from "next/cache";

import { call, failureMessages } from "./action-call";
import { checkModel, type ModelCheck } from "./openrouter-models";

/** What a plan's new-version form shows after an attempt. */
export type PlanFormState = { message: string | null };

const modelMessages: Record<Exclude<ModelCheck, "usable">, string> = {
  unknown: "OpenRouter에 없는 모델이에요. 모델 ID를 확인해 주세요.",
  unsuitable: "사진과 구조화된 답을 함께 지원하지 않는 모델이에요.",
  unreachable: "OpenRouter에 연결할 수 없어 모델을 확인하지 못했어요. 잠시 후 다시 시도해 주세요.",
};

/**
 * Creates a version of the form's `plan` on its `quota`, `amount` and `model`, from 00:00 Asia/Seoul
 * on `starts_on`, or from now when it is empty, for existing users too when `applies_to_all` is
 * checked (ADR 0097). The model must be one OpenRouter lists with image input and structured
 * outputs; the server checks the role, the terms and the start, and records the version.
 */
export async function createPlanVersion(
  _previous: PlanFormState,
  form: FormData,
): Promise<PlanFormState> {
  const plan = form.get("plan");
  const quota = form.get("quota");
  const model = form.get("model");
  const amountValue = form.get("amount");
  const startsOn = form.get("starts_on");
  if (plan !== "free" && plan !== "pro" && plan !== "max") {
    return { message: failureMessages.malformed };
  }
  if (quota !== "monthly" && quota !== "daily" && quota !== "unlimited") {
    return { message: failureMessages.malformed };
  }
  if (typeof model !== "string" || !/^[A-Za-z0-9_.-]+\/[A-Za-z0-9_.:-]+$/.test(model.trim())) {
    return { message: "모델 ID는 vendor/model 꼴로 적어 주세요." };
  }
  const amount =
    typeof amountValue === "string" && /^\d+$/.test(amountValue.trim()) ? Number(amountValue) : NaN;
  if (!Number.isInteger(amount) || amount > 100_000) {
    return { message: "사진 장 수는 0에서 100000 사이의 정수로 적어 주세요." };
  }
  let startsAt: string | null = null;
  if (typeof startsOn === "string" && startsOn !== "") {
    if (!/^\d{4}-\d{2}-\d{2}$/.test(startsOn)) return { message: failureMessages.malformed };
    // Asia/Seoul is UTC+9 all year, with no daylight saving time.
    const start = Date.parse(`${startsOn}T00:00:00+09:00`);
    if (Number.isNaN(start)) return { message: failureMessages.malformed };
    startsAt = new Date(start).toISOString();
  }
  const check = await checkModel(model.trim());
  if (check !== "usable") return { message: modelMessages[check] };
  const result = await call("admin_create_plan_version", {
    plan,
    quota,
    amount,
    model: model.trim(),
    starts_at: startsAt,
    applies_to_all: form.get("applies_to_all") === "on",
  });
  if ("failure" in result) return { message: failureMessages[result.failure] };
  switch (result.data) {
    case "created":
      revalidatePath("/admin", "layout");
      return { message: "새 버전을 만들었어요." };
    case "unchanged":
      return { message: "지금 버전과 같아요." };
    case "past_start":
      return { message: "시작일은 내일 이후로 정하거나, 지금부터면 비워 두세요." };
    case "not_in_favour":
      return {
        message:
          "기존 사용자에게 바로 적용할 수 있는 건 같은 모델에서 사진을 줄이지 않는 변경뿐이에요.",
      };
    default:
      return { message: failureMessages.unreadable };
  }
}
