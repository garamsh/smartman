import "server-only";

import { createClient } from "@/lib/supabase/server";
import { readSession, type Session } from "@/lib/supabase/session";

/** The session of the request being rendered, verified with Supabase Auth. */
export async function getSession(): Promise<Session> {
  return readSession(await createClient());
}
