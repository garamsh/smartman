"use server";

import { redirect } from "next/navigation";

import { createClient } from "@/lib/supabase/server";

/** What the sign-out form shows after a failed attempt. */
export type SignOutState = { error: string | null };

/**
 * Ends this browser's session, and only this one: the phone and other browsers stay signed
 * in. Then opens `/login`, or returns the reason when Supabase Auth could not be reached.
 */
export async function signOut(_previous: SignOutState): Promise<SignOutState> {
  const supabase = await createClient();
  const { error } = await supabase.auth.signOut({ scope: "local" });
  if (error) {
    return { error: "로그아웃하지 못했어요. 연결을 확인하고 다시 시도해 주세요." };
  }
  redirect("/login");
}
