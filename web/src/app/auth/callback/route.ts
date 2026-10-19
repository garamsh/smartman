import { NextResponse, type NextRequest } from "next/server";

import { createClient } from "@/supabase/server";

/**
 * Where Google sign-in returns through Supabase Auth: exchanges the code for a session
 * cookie and opens the app, or opens `/login` with the reason.
 */
export async function GET(request: NextRequest) {
  const code = request.nextUrl.searchParams.get("code");
  const target = request.nextUrl.clone();
  target.search = "";

  if (!code) {
    // Supabase sends `error` instead of a code: `user_banned` for a suspended account (ADR 0072),
    // otherwise `access_denied` is the user cancelling at Google.
    const params = request.nextUrl.searchParams;
    const reason =
      params.get("error_code") === "user_banned"
        ? "suspended"
        : params.get("error") === "access_denied"
          ? "cancelled"
          : "failed";
    target.pathname = "/login";
    target.searchParams.set("error", reason);
    return NextResponse.redirect(target);
  }

  const supabase = await createClient();
  const { error } = await supabase.auth.exchangeCodeForSession(code);
  if (error) {
    target.pathname = "/login";
    target.searchParams.set("error", error.code === "user_banned" ? "suspended" : "failed");
    return NextResponse.redirect(target);
  }
  target.pathname = "/";
  return NextResponse.redirect(target);
}
