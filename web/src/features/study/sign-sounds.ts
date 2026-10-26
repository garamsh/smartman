import "server-only";

import { createClient } from "@/supabase/server";
import { readUserId } from "@/supabase/session";

/** How long a sound's signed address plays, in seconds: longer than a study session runs. */
export const soundUrlSeconds = 4 * 60 * 60;

/**
 * A signed address in the private `media` bucket for each of [media], the signed-in user's
 * sounds, each at `{owner}/{media id}` (ADR 0107, ADR 0112), in one request. A sound the
 * bucket cannot sign, and every sound when the request fails, has none, so its control says it
 * cannot play rather than the page failing.
 */
export async function signSounds(media: string[]): Promise<Map<string, string>> {
  const signed = new Map<string, string>();
  if (media.length === 0) return signed;
  const supabase = await createClient();
  const session = await readUserId(supabase);
  if ("failure" in session) return signed;
  const owner = session.userId;
  // Storage answers a failure, an unreachable server's included, as an error with no data.
  const { data } = await supabase.storage.from("media").createSignedUrls(
    media.map((id) => `${owner}/${id}`),
    soundUrlSeconds,
  );
  for (const entry of data ?? []) {
    const id = entry.path?.slice(owner.length + 1);
    if (id && !entry.error && entry.signedUrl) signed.set(id, entry.signedUrl);
  }
  return signed;
}
