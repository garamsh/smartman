import "server-only";

import { createServerClient } from "@supabase/ssr";
import { cookies } from "next/headers";
import { connection } from "next/server";

import { env } from "@/env";

/** A Supabase client for a Server Component, Server Action or Route Handler, over the request's cookies. */
export async function createClient() {
  // The client reads the clock as it starts, which a prerender, a prefetch's included, refuses;
  // waiting for the request first leaves the render using it to request time.
  await connection();
  const cookieStore = await cookies();
  return createServerClient(env.supabaseUrl, env.supabasePublishableKey, {
    cookies: {
      getAll: () => cookieStore.getAll(),
      setAll: (cookiesToSet) => {
        try {
          for (const { name, value, options } of cookiesToSet) {
            cookieStore.set(name, value, options);
          }
        } catch {
          // A Server Component cannot set cookies; the proxy has already refreshed the session.
        }
      },
    },
  });
}
