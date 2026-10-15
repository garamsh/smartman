import type { PostgrestError } from "@supabase/supabase-js";

/** Why a request to the server's tables failed. */
export type ServerFailure =
  /** No connection, no answer in time, or the server or its gateway is down. */
  | "unreachable"
  /** The session or a row-level security policy refused the request. */
  | "rejected"
  /** The server refused the request or answered with something unreadable. */
  | "failed";

/**
 * The failure a PostgREST [error] with HTTP [status] means, by the codes `sync.md` maps for
 * the phone. A request that never got an answer has status 0.
 */
export function classifyFailure(error: PostgrestError, status: number): ServerFailure {
  if (status === 0) return "unreachable";
  switch (error.code) {
    case "42501":
    case "PGRST301":
    case "PGRST302":
      return "rejected";
    case "PGRST000":
    case "PGRST001":
    case "PGRST002":
      return "unreachable";
  }
  if (status === 401 || status === 403) return "rejected";
  if (status === 500 || status === 502 || status === 503 || status === 504) return "unreachable";
  return "failed";
}

/** How long one request may take before it counts as unreachable, as on the phone. */
export const requestTimeoutMs = 20_000;
