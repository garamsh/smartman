import { createServerClient } from "@supabase/ssr";
import { NextResponse, type NextRequest } from "next/server";

import { env } from "@/env";
import { readSession } from "@/supabase/session";

/** The paths a signed-out visitor may open; `/api` is outside the matcher. */
const publicPaths = new Set(["/login", "/auth/callback", "/terms", "/privacy"]);

/**
 * Refreshes the Supabase session on every matched request and sends a signed-out visitor
 * to `/login`, keeping an AI app's consent to return to after sign-in (ADR 0126). Server Actions
 * re-verify the session themselves (stack-nextjs §5).
 */
export async function proxy(request: NextRequest) {
  let response = NextResponse.next({ request });
  const supabase = createServerClient(env.supabaseUrl, env.supabasePublishableKey, {
    cookies: {
      getAll: () => request.cookies.getAll(),
      setAll: (cookiesToSet, headers) => {
        for (const { name, value } of cookiesToSet) request.cookies.set(name, value);
        response = NextResponse.next({ request });
        for (const { name, value, options } of cookiesToSet) {
          response.cookies.set(name, value, options);
        }
        for (const [name, value] of Object.entries(headers)) response.headers.set(name, value);
      },
    },
  });

  const session = await readSession(supabase);
  const { pathname, searchParams } = request.nextUrl;
  if (session.kind === "signed-out" && !publicPaths.has(pathname)) {
    const login = request.nextUrl.clone();
    login.pathname = "/login";
    login.search = "";
    const redirect = NextResponse.redirect(login);
    for (const cookie of response.cookies.getAll()) redirect.cookies.set(cookie);
    const authorization = searchParams.get("authorization_id");
    if (pathname === "/oauth/consent" && authorization && AUTHORIZATION_ID.test(authorization)) {
      redirect.cookies.set(consentCookie, authorization, {
        httpOnly: true,
        sameSite: "lax",
        secure: request.nextUrl.protocol === "https:",
        path: "/",
        maxAge: consentCookieSeconds,
      });
    }
    return redirect;
  }
  // Sign-in always opens `/`: an AI app's consent the visitor left to sign in opens instead, once.
  const pending = request.cookies.get(consentCookie)?.value;
  if (session.kind === "signed-in" && pathname === "/" && pending !== undefined) {
    if (!AUTHORIZATION_ID.test(pending)) {
      response.cookies.delete(consentCookie);
      return response;
    }
    const consent = request.nextUrl.clone();
    consent.pathname = "/oauth/consent";
    consent.search = `?authorization_id=${pending}`;
    const redirect = NextResponse.redirect(consent);
    for (const cookie of response.cookies.getAll()) redirect.cookies.set(cookie);
    redirect.cookies.delete(consentCookie);
    return redirect;
  }
  return response;
}

/** The cookie holding the id of the consent a signed-out visitor was sent from to `/login`. */
const consentCookie = "smartman-oauth-consent";
/** As long as Supabase Auth keeps an authorization open: ten minutes. */
const consentCookieSeconds = 600;
/** The form of Supabase Auth's authorization ids, the only value the cookie may carry. */
const AUTHORIZATION_ID = /^[A-Za-z0-9_-]{1,128}$/;

export const config = {
  // The files under public/, the icons, the manifest and brand/, are served to everyone.
  matcher: [
    "/((?!api|_next/static|_next/image|favicon.ico|brand/|.*\\.(?:svg|png|webmanifest)$).*)",
  ],
};
