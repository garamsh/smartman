"use client";

import { useActionState } from "react";

import { grantAdmin, type GrantState } from "../grant-admin";

/** Grants the admin role to the existing user an email names. */
export function GrantAdminForm() {
  const [state, action, pending] = useActionState<GrantState, FormData>(grantAdmin, {
    message: null,
  });
  return (
    <form action={action} className="flex flex-col gap-2">
      <label htmlFor="grant-email" className="text-label font-semibold">
        관리자 지정
      </label>
      <div className="flex flex-wrap gap-2">
        <input
          id="grant-email"
          type="email"
          name="email"
          required
          placeholder="가입한 사용자의 이메일"
          className="h-search min-w-0 flex-1 rounded-field border border-outline bg-surface px-4 text-body placeholder:text-muted focus-visible:outline-2 focus-visible:-outline-offset-1 focus-visible:outline-ink"
        />
        <button
          type="submit"
          disabled={pending}
          className="flex min-h-button items-center justify-center rounded-button bg-ink px-5 text-label font-semibold text-surface focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-ink disabled:opacity-50"
        >
          지정
        </button>
      </div>
      <p role="status" className="text-caption text-muted empty:hidden">
        {state.message}
      </p>
    </form>
  );
}
