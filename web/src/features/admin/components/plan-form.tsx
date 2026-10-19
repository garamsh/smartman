"use client";

import { useActionState } from "react";

import { type PlanFormState, setPlan } from "../admin-actions";

const field =
  "h-search w-full rounded-field border border-outline bg-surface px-4 text-body focus-visible:outline-2 focus-visible:-outline-offset-1 focus-visible:outline-ink";

/** One plan's model and daily limit, saved together. */
export function PlanForm({
  plan,
  name,
  model,
  dailyLimit,
}: {
  plan: string;
  name: string;
  model: string;
  dailyLimit: number;
}) {
  const [state, action, pending] = useActionState<PlanFormState, FormData>(setPlan, {
    message: null,
  });
  return (
    <form action={action} aria-label={`${name} 설정`} className="flex flex-col gap-3">
      <input type="hidden" name="plan" value={plan} />
      <label className="flex flex-col gap-1">
        <span className="text-label font-semibold">모델</span>
        <input name="model" defaultValue={model} required className={field} />
      </label>
      <label className="flex flex-col gap-1">
        <span className="text-label font-semibold">하루 사진 한도</span>
        <input
          name="daily_limit"
          type="number"
          min={0}
          max={1000}
          defaultValue={dailyLimit}
          required
          className={field}
        />
      </label>
      <button
        type="submit"
        disabled={pending}
        className="flex min-h-button items-center justify-center rounded-button bg-ink px-5 text-label font-semibold text-surface focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-ink disabled:opacity-50"
      >
        저장
      </button>
      <p role="status" className="text-caption text-muted empty:hidden">
        {state.message}
      </p>
    </form>
  );
}
