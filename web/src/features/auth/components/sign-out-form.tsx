"use client";

import { LogOut } from "lucide-react";
import { useActionState } from "react";

import { signOut } from "../actions";

/** The sign-out row, with the reason beneath it when sign-out fails. */
export function SignOutForm() {
  const [state, action, pending] = useActionState(signOut, { error: null });
  return (
    <form action={action} className="flex flex-col gap-3">
      <button
        type="submit"
        disabled={pending}
        className="flex min-h-13 items-center gap-3 rounded-row bg-surface px-4 py-3 text-left text-body font-bold text-ink focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-ink disabled:opacity-50"
      >
        <LogOut aria-hidden className="size-5" strokeWidth={2} />
        로그아웃
      </button>
      {state.error && (
        <p role="alert" className="text-secondary text-dont-know-text">
          {state.error}
        </p>
      )}
    </form>
  );
}
