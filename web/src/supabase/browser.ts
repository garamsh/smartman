import { createBrowserClient } from "@supabase/ssr";

import { env } from "@/env";

/** A Supabase client for a Client Component, keeping the session in the same cookies the server reads. */
export function createClient() {
  return createBrowserClient(env.supabaseUrl, env.supabasePublishableKey);
}
