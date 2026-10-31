"use client";

import { useActionState } from "react";

import { grantAdmin, type GrantState } from "../grant-admin";
import { button, field, group } from "./admin-section";

/** Grants the admin role to the existing user an email names. */
export function GrantAdminForm() {
  const [state, action, pending] = useActionState<GrantState, FormData>(grantAdmin, {
    message: null,
  });
  return (
    <form action={action} className="flex flex-col gap-2">
      <label htmlFor="grant-email" className="px-1 text-section text-muted">
        관리자 지정
      </label>
      <div className={group}>
        <input
          id="grant-email"
          type="email"
          name="email"
          required
          placeholder="가입한 사용자의 이메일"
          className={`${field} h-button px-4`}
        />
      </div>
      <button type="submit" disabled={pending} className={button.primary}>
        지정
      </button>
      <p role="status" className="text-caption text-muted empty:hidden">
        {state.message}
      </p>
    </form>
  );
}
