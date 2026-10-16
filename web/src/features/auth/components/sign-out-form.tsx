"use client";

import { LoaderCircle, LogOut } from "lucide-react";
import { useActionState } from "react";

import { signOut } from "../actions";

/**
 * The sign-out row, showing progress in place of its icon while sign-out runs, and the reason
 * beneath it when sign-out fails.
 */
export function SignOutForm() {
  const [state, action, pending] = useActionState(signOut, { error: null });
  return (
    <form action={action} className="flex flex-col gap-3">
      <button
        type="submit"
        disabled={pending}
        aria-busy={pending}
        className="flex min-h-button items-center gap-3 rounded-row bg-surface px-4 py-3 text-left text-body-strong text-ink focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-ink disabled:opacity-50"
      >
        {pending ? (
          <LoaderCircle aria-hidden className="size-5 motion-safe:animate-spin" strokeWidth={2} />
        ) : (
          <LogOut aria-hidden className="size-5" strokeWidth={2} />
        )}
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
