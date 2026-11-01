"use client";

import { useActionState } from "react";

import { grantPlan, type GrantPlanState } from "../grant-plan";

const field =
  "h-search rounded-field border border-outline bg-surface px-4 text-body focus-visible:outline-2 focus-visible:-outline-offset-1 focus-visible:outline-ink";

/** Puts a user on Pro, or on Max with an optional last day. */
export function GrantPlanForm({ userId }: { userId: string }) {
  const [state, action, pending] = useActionState<GrantPlanState, FormData>(grantPlan, {
    message: null,
  });
  return (
    <form action={action} aria-label="요금제 지정" className="flex flex-col gap-3">
      <input type="hidden" name="user" value={userId} />
      <div className="flex flex-wrap gap-3">
        <label className="flex flex-col gap-1">
          <span className="text-label font-semibold">요금제</span>
          <select name="plan" defaultValue="pro" className={field}>
            <option value="pro">프로</option>
            <option value="max">맥스</option>
          </select>
        </label>
        <label className="flex flex-col gap-1">
          <span className="text-label font-semibold">마지막 날 (맥스만, 비우면 끝없음)</span>
          <input type="date" name="ends_on" className={field} />
        </label>
      </div>
      <button
        type="submit"
        disabled={pending}
        className="pressable flex min-h-button items-center justify-center self-start rounded-button bg-ink px-5 text-label font-semibold text-surface focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-ink disabled:opacity-50"
      >
        지정
      </button>
      <p role="status" className="text-caption text-muted empty:hidden">
        {state.message}
      </p>
    </form>
  );
}
