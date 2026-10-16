import "server-only";

import { createClient } from "@/supabase/server";
import { readSession, type Session } from "@/supabase/session";

/** The session of the request being rendered, verified with Supabase Auth. */
export async function getSession(): Promise<Session> {
  return readSession(await createClient());
}
