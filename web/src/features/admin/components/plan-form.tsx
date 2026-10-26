"use client";

import { useActionState } from "react";

import { createPlanVersion, type PlanFormState } from "../create-plan-version";
import type { Quota } from "../read-admin";

const field =
  "h-search w-full rounded-field border border-outline bg-surface px-4 text-body focus-visible:outline-2 focus-visible:-outline-offset-1 focus-visible:outline-ink";

/** A new version of one plan's terms, starting from the current version's. */
export function PlanForm({
  plan,
  name,
  quota,
  amount,
  model,
}: {
  plan: string;
  name: string;
  quota: Quota;
  amount: number;
  model: string;
}) {
  const [state, action, pending] = useActionState<PlanFormState, FormData>(createPlanVersion, {
    message: null,
  });
  return (
    <form action={action} aria-label={`${name} 새 버전`} className="flex flex-col gap-3">
      <input type="hidden" name="plan" value={plan} />
      <label className="flex flex-col gap-1">
        <span className="text-label font-semibold">한도</span>
        <select name="quota" defaultValue={quota} className={field}>
          <option value="monthly">한 달에</option>
          <option value="daily">하루에</option>
          <option value="unlimited">무제한 (하루 공정 사용 한도)</option>
        </select>
      </label>
      <label className="flex flex-col gap-1">
        <span className="text-label font-semibold">사진 장 수</span>
        <input
          name="amount"
          type="number"
          min={0}
          max={100_000}
          defaultValue={amount}
          required
          className={field}
        />
      </label>
      <label className="flex flex-col gap-1">
        <span className="text-label font-semibold">모델</span>
        <input name="model" defaultValue={model} required className={field} />
      </label>
      <label className="flex flex-col gap-1">
        <span className="text-label font-semibold">시작일 (비우면 지금부터)</span>
        <input type="date" name="starts_on" className={field} />
      </label>
      <label className="flex items-start gap-2">
        <input type="checkbox" name="applies_to_all" className="mt-1 size-4 accent-ink" />
        <span className="text-secondary">
          기존 사용자에게도 시작일부터 적용 (사용자에게 유리한 변경만, 아니면 다음 갱신일인 매월
          1일부터)
        </span>
      </label>
      <button
        type="submit"
        disabled={pending}
        className="pressable flex min-h-button items-center justify-center rounded-button bg-ink px-5 text-label font-semibold text-surface focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-ink disabled:opacity-50"
      >
        새 버전 만들기
      </button>
      <p role="status" className="text-caption text-muted empty:hidden">
        {state.message}
      </p>
    </form>
  );
}
