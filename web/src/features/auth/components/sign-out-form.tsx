"use client";

import { useActionState } from "react";

import { signOut } from "../actions";

/** The sign-out button, with the reason beneath it when sign-out fails. */
export function SignOutForm() {
  const [state, action, pending] = useActionState(signOut, { error: null });
  return (
    <form action={action} className="flex flex-col gap-3">
      <button
        type="submit"
        disabled={pending}
        className="min-h-13 rounded-row border border-hairline bg-surface px-6 font-semibold text-ink focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-ink disabled:opacity-50"
      >
        로그아웃
      </button>
      {state.error && (
        <p role="alert" className="text-sm text-dont-know-text">
          {state.error}
        </p>
      )}
    </form>
  );
}
