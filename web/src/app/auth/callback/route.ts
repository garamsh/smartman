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
    // Supabase sends `error` instead of a code; `access_denied` is the user cancelling at Google.
    const cancelled = request.nextUrl.searchParams.get("error") === "access_denied";
    target.pathname = "/login";
    target.searchParams.set("error", cancelled ? "cancelled" : "failed");
    return NextResponse.redirect(target);
  }

  const supabase = await createClient();
  const { error } = await supabase.auth.exchangeCodeForSession(code);
  if (error) {
    target.pathname = "/login";
    target.searchParams.set("error", "failed");
    return NextResponse.redirect(target);
  }
  target.pathname = "/";
  return NextResponse.redirect(target);
}
