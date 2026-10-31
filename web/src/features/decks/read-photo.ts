"use server";

import { env } from "@/env";
import { createClient } from "@/supabase/server";
import { readUserId } from "@/supabase/session";
import { field } from "@/supabase/row";
import { parseCandidates, type Candidate } from "./photo-candidates";
import type { PhotoFailure } from "./photo-failure";

/** A per-photo result, without exposing service errors or credentials. */
export type Extraction = { cards: Candidate[] } | { failure: PhotoFailure };

/** The upload bound: the browser prepares every photo under it, inside the 4 MiB action limit. */
const maxUploadBytes = 3 * 1024 * 1024;

/**
 * Calls the existing extraction function as the verified user, without a browser CORS request,
 * and logs one line per photo with the function's status and latency, never the image or token.
 */
export async function readPhoto(form: FormData): Promise<Extraction> {
  if (!(form instanceof FormData)) return { failure: { kind: "refused" } };
  const file = form.get("photo");
  if (!(file instanceof File) || file.size === 0 || file.size > maxUploadBytes)
    return { failure: { kind: "refused" } };
  const client = await createClient();
  const user = await readUserId(client);
  if ("failure" in user)
    return { failure: { kind: user.failure === "unreachable" ? "service" : "signIn" } };
  const session = await client.auth.getSession();
  const token = session.data.session?.access_token;
  if (!token) return { failure: { kind: "signIn" } };
  const bytes = new Uint8Array(await file.arrayBuffer());
  const jpeg = bytes[0] === 255 && bytes[1] === 216 && bytes[2] === 255;
  const png = bytes[0] === 137 && bytes[1] === 80 && bytes[2] === 78 && bytes[3] === 71;
  const webp =
    String.fromCharCode(...bytes.slice(0, 4)) === "RIFF" &&
    String.fromCharCode(...bytes.slice(8, 12)) === "WEBP";
  if (!jpeg && !png && !webp) return { failure: { kind: "refused" } };
  const body = JSON.stringify({ image: Buffer.from(bytes).toString("base64") });
  const started = Date.now();
  let attempts = 0;
  let status: number | "timeout" | "unreachable" = "unreachable";
  let result: Extraction = { failure: { kind: "service" } };
  // A request that got no response may never have reached the function, so it is sent once more;
  // a timeout or any answer is not, since the function counts a photo before calling the model.
  while (attempts < 2 && status === "unreachable") {
    attempts += 1;
    try {
      const response = await fetch(
        `${env.supabaseUrl.replace(/\/$/u, "")}/functions/v1/extract-cards`,
        {
          method: "POST",
          headers: {
            Authorization: `Bearer ${token}`,
            apikey: env.supabasePublishableKey,
            "Content-Type": "application/json",
          },
          body,
          signal: AbortSignal.timeout(90_000),
        },
      );
      status = response.status;
      result = parseExtraction(response.status, await response.json().catch(() => null));
    } catch (cause) {
      status =
        cause instanceof DOMException && cause.name === "TimeoutError" ? "timeout" : "unreachable";
    }
  }
  console.info(
    JSON.stringify({
      event: "read_photo",
      status,
      ms: Date.now() - started,
      attempts,
      bytes: bytes.length,
      outcome: "cards" in result ? "cards" : result.failure.kind,
      cards: "cards" in result ? result.cards.length : 0,
    }),
  );
  return result;
}

/** The cards a 200 holds, or the failure a status means, as the phone's `parseExtraction`. */
function parseExtraction(status: number, body: unknown): Extraction {
  if (status === 200) {
    const cards = parseCandidates(body);
    return cards ? { cards } : { failure: { kind: "service" } };
  }
  if (status === 401) return { failure: { kind: "signIn" } };
  if (status === 403 && field(body, "error") === "suspended")
    return { failure: { kind: "suspended" } };
  if (status === 413 || status === 415) return { failure: { kind: "refused" } };
  if (status === 422) return { failure: { kind: "noCards" } };
  if (status === 429) {
    const limit = field(body, "photo_limit");
    const period = field(body, "period");
    if (
      typeof limit === "number" &&
      Number.isInteger(limit) &&
      limit >= 0 &&
      (period === "day" || period === "month")
    )
      return { failure: { kind: "limit", limit, period } };
  }
  if (status === 502) return { failure: { kind: "model" } };
  return { failure: { kind: "service" } };
}
