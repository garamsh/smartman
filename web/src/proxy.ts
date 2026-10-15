import { createServerClient } from "@supabase/ssr";
import { NextResponse, type NextRequest } from "next/server";

import { env } from "@/env";
import { readSession } from "@/lib/supabase/session";

/** The paths a signed-out visitor may open; `/api` is outside the matcher. */
const publicPaths = new Set(["/login", "/auth/callback"]);

/**
 * Refreshes the Supabase session on every matched request and sends a signed-out visitor
 * to `/login`. Server Actions re-verify the session themselves (stack-nextjs §5).
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
  if (session.kind === "signed-out" && !publicPaths.has(request.nextUrl.pathname)) {
    const login = request.nextUrl.clone();
    login.pathname = "/login";
    login.search = "";
    const redirect = NextResponse.redirect(login);
    for (const cookie of response.cookies.getAll()) redirect.cookies.set(cookie);
    return redirect;
  }
  return response;
}

export const config = {
  // The files under public/, the icons, the manifest and brand/, are served to everyone.
  matcher: [
    "/((?!api|_next/static|_next/image|favicon.ico|brand/|.*\\.(?:svg|png|webmanifest)$).*)",
  ],
};
