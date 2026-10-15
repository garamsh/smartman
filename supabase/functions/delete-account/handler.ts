/** The delete-account request pipeline and the mapping from each outcome to an HTTP status. */

import { authenticate, SupabaseError, type UserId } from "../_shared/auth.ts";
import { deleteUser } from "./admin.ts";
import type { Config } from "./config.ts";

/** How a request ended; a refusal's body carries the same code. */
export type Outcome =
  | "deleted"
  | "method_not_allowed"
  | "not_configured"
  | "unauthenticated"
  | "delete_failed"
  | "internal";

/** The one line logged per request. It carries these fields only: never the token or a key. */
export type LogEntry = {
  readonly user_id: UserId | null;
  readonly outcome: Outcome;
};

export type HandlerDeps = {
  readonly config: Config;
  readonly fetch: typeof fetch;
  readonly log: (entry: LogEntry) => void;
};

export function status(outcome: Outcome): number {
  switch (outcome) {
    case "deleted":
      return 204;
    case "unauthenticated":
      return 401;
    case "method_not_allowed":
      return 405;
    case "internal":
      return 500;
    case "delete_failed":
      return 502;
    case "not_configured":
      return 503;
  }
}

type Result = { readonly outcome: Outcome; readonly userId: UserId | null };

export function createHandler(
  deps: HandlerDeps,
): (request: Request) => Promise<Response> {
  return async (request) => {
    let result: Result;
    try {
      result = await handle(request, deps);
    } catch (error) {
      deps.log({ user_id: null, outcome: "internal" });
      throw error;
    }
    deps.log({ user_id: result.userId, outcome: result.outcome });
    return result.outcome === "deleted"
      ? new Response(null, { status: 204 })
      : Response.json({ error: result.outcome }, {
        status: status(result.outcome),
      });
  };
}

/** The user deleted is always the token's: the body is never read. */
async function handle(request: Request, deps: HandlerDeps): Promise<Result> {
  if (request.method !== "POST") {
    return { outcome: "method_not_allowed", userId: null };
  }
  const config = deps.config;
  if (config.kind === "not_configured") {
    return { outcome: "not_configured", userId: null };
  }
  const supabase = {
    url: config.supabaseUrl,
    serviceRoleKey: config.serviceRoleKey,
    fetch: deps.fetch,
  };
  let userId: UserId | null = null;
  try {
    userId = await authenticate(request.headers.get("Authorization"), supabase);
    if (userId === null) return { outcome: "unauthenticated", userId };
    await deleteUser(userId, supabase);
  } catch (error) {
    if (error instanceof SupabaseError) {
      return { outcome: "delete_failed", userId };
    }
    throw error;
  }
  return { outcome: "deleted", userId };
}
