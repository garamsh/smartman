"use client";

import { useState } from "react";

import { createClient } from "@/lib/supabase/browser";

/**
 * Starts Google sign-in through Supabase Auth. The browser leaves for Google and comes back
 * to `/auth/callback` on this origin, which must be in Supabase Auth's allowed redirect URLs.
 */
export function SignInButton() {
  const [state, setState] = useState<"idle" | "pending" | "failed">("idle");

  async function signIn() {
    setState("pending");
    const { error } = await createClient().auth.signInWithOAuth({
      provider: "google",
      options: { redirectTo: `${window.location.origin}/auth/callback` },
    });
    // On success the browser is already navigating to Google.
    if (error) setState("failed");
  }

  return (
    <div className="flex flex-col gap-3">
      <button
        type="button"
        onClick={() => void signIn()}
        disabled={state === "pending"}
        className="min-h-13 rounded-row bg-ink px-6 font-semibold text-surface focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-ink disabled:opacity-50"
      >
        Google로 로그인
      </button>
      {state === "failed" && (
        <p role="alert" className="text-sm text-dont-know-text">
          로그인을 시작하지 못했어요. 다시 시도해 주세요.
        </p>
      )}
    </div>
  );
}
