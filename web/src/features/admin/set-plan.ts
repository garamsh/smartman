"use server";

import { revalidatePath } from "next/cache";

import { call, failureMessages } from "./action-call";
import { checkModel, type ModelCheck } from "./openrouter-models";

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
