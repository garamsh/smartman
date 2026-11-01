/**
 * The MCP server over Streamable HTTP: the protected resource metadata, the bearer check with its
 * 401 challenge, and JSON-RPC requests answered as JSON, with no session, at the protocol
 * versions that open with `initialize` (ADR 0126).
 */

import { SupabaseError, type UserId } from "../_shared/auth.ts";
import { authorize } from "./authorize.ts";
import type { IdSource } from "./cards.ts";
import type { Config } from "./config.ts";
import { callTool, TOOLS } from "./tools.ts";

/** The protocol versions served, newest first; `initialize` answers the newest it is not offered. */
export const PROTOCOL_VERSIONS = [
  "2025-11-25",
  "2025-06-18",
  "2025-03-26",
] as const;

const METADATA_SUFFIX = "/oauth-protected-resource";

/** How a request ended. */
export type Outcome =
  | "answered"
  | "tool_refused"
  | "metadata"
  | "notification"
  | "unauthenticated"
  | "forbidden_origin"
  | "method_not_allowed"
  | "not_found"
  | "bad_request"
  | "not_configured"
  | "unavailable";

/** The one line logged per request: never the token, a key, or a card's content. */
export type LogEntry = {
  readonly user_id: UserId | null;
  readonly method: string | null;
  readonly tool: string | null;
  readonly outcome: Outcome;
};

export type HandlerDeps = IdSource & {
  readonly config: Config;
  readonly fetch: typeof fetch;
  readonly log: (entry: LogEntry) => void;
};

const INSTRUCTIONS =
  "Smartman is a flashcard app. These tools read the signed-in user's decks and cards and add new decks and cards; they never change or delete anything. Find a deck's id with list_decks, read a deck with list_cards, find cards with search_cards, make a deck with create_deck and add cards with add_cards. New cards reach the user's phone and the web at their next sync.";

type Exchange = {
  response: Response;
  entry: Omit<LogEntry, "outcome"> & { outcome: Outcome };
};

const empty = { user_id: null, method: null, tool: null };

function rpcError(id: unknown, code: number, message: string) {
  return { jsonrpc: "2.0", id: id ?? null, error: { code, message } };
}

export function createHandler(
  deps: HandlerDeps,
): (request: Request) => Promise<Response> {
  return async (request) => {
    let exchange: Exchange;
    try {
      exchange = await handle(request, deps);
    } catch (error) {
      deps.log({ ...empty, outcome: "unavailable" });
      throw error;
    }
    deps.log(exchange.entry);
    return exchange.response;
  };
}

async function handle(request: Request, deps: HandlerDeps): Promise<Exchange> {
  const path = new URL(request.url).pathname.replace(/\/$/, "");
  const config = deps.config;
  if (config.kind === "not_configured") {
    return {
      response: Response.json(
        rpcError(null, -32603, "The server is not configured"),
        {
          status: 503,
        },
      ),
      entry: { ...empty, outcome: "not_configured" },
    };
  }
  const resource = config.resourceUrl;
  if (path === `/mcp${METADATA_SUFFIX}`) {
    if (request.method !== "GET") {
      return {
        response: new Response(null, {
          status: 405,
          headers: { Allow: "GET" },
        }),
        entry: { ...empty, outcome: "method_not_allowed" },
      };
    }
    return {
      response: Response.json({
        resource,
        // Auth's issuer, which RFC 8414 requires this to equal, stays on the project's host.
        authorization_servers: [`${config.projectOrigin}/auth/v1`],
        bearer_methods_supported: ["header"],
        resource_name: "smartman",
      }),
      entry: { ...empty, outcome: "metadata" },
    };
  }
  if (path !== "/mcp") {
    return {
      response: Response.json({ error: "not_found" }, { status: 404 }),
      entry: { ...empty, outcome: "not_found" },
    };
  }
  // No browser is a client: a request carrying an Origin is refused against DNS rebinding.
  if (request.headers.has("Origin")) {
    return {
      response: Response.json(rpcError(null, -32600, "Origin not allowed"), {
        status: 403,
      }),
      entry: { ...empty, outcome: "forbidden_origin" },
    };
  }
  if (request.method !== "POST") {
    return {
      response: new Response(null, { status: 405, headers: { Allow: "POST" } }),
      entry: { ...empty, outcome: "method_not_allowed" },
    };
  }
  let caller;
  try {
    caller = await authorize(request.headers.get("Authorization"), {
      url: config.supabaseUrl,
      anonKey: config.anonKey,
      fetch: deps.fetch,
    });
  } catch (error) {
    if (error instanceof SupabaseError) return unavailable(null, null, null);
    throw error;
  }
  if (caller === null) {
    const metadata = `${resource}${METADATA_SUFFIX}`;
    const challenge = request.headers.has("Authorization")
      ? `Bearer error="invalid_token", error_description="The access token is missing its connection, expired or was revoked; sign in again", resource_metadata="${metadata}"`
      : `Bearer resource_metadata="${metadata}"`;
    return {
      response: Response.json({ error: "unauthenticated" }, {
        status: 401,
        headers: { "WWW-Authenticate": challenge },
      }),
      entry: { ...empty, outcome: "unauthenticated" },
    };
  }
  let message: unknown;
  try {
    message = await request.json();
  } catch {
    return badRequest(
      caller.userId,
      rpcError(null, -32700, "The body is not JSON"),
    );
  }
  if (
    typeof message !== "object" || message === null || Array.isArray(message)
  ) {
    return badRequest(
      caller.userId,
      rpcError(
        null,
        -32600,
        "The body must be one JSON-RPC message; batches are not supported",
      ),
    );
  }
  const body = message as Record<string, unknown>;
  // A notification, or a response to a request this server never sends, needs no answer.
  if (!("id" in body) || !("method" in body)) {
    return {
      response: new Response(null, { status: 202 }),
      entry: {
        user_id: caller.userId,
        method: typeof body.method === "string" ? body.method : null,
        tool: null,
        outcome: "notification",
      },
    };
  }
  const { id, method } = body;
  if (
    (typeof id !== "string" && typeof id !== "number") ||
    typeof method !== "string"
  ) {
    return badRequest(
      caller.userId,
      rpcError(null, -32600, "Invalid JSON-RPC request"),
    );
  }
  const version = request.headers.get("MCP-Protocol-Version");
  if (
    method !== "initialize" && version !== null &&
    !(PROTOCOL_VERSIONS as readonly string[]).includes(version)
  ) {
    return badRequest(
      caller.userId,
      rpcError(
        id,
        -32600,
        `Unsupported protocol version ${version}; this server speaks ${
          PROTOCOL_VERSIONS.join(", ")
        } after initialize`,
      ),
      method,
    );
  }
  const params = typeof body.params === "object" && body.params !== null
    ? body.params as Record<string, unknown>
    : {};
  const answer = (
    result: unknown,
    outcome: Outcome = "answered",
    tool: string | null = null,
  ) => ({
    response: Response.json({ jsonrpc: "2.0", id, result }),
    entry: { user_id: caller.userId, method, tool, outcome },
  });
  switch (method) {
    case "initialize": {
      const offered = params.protocolVersion;
      const protocolVersion =
        (PROTOCOL_VERSIONS as readonly unknown[]).includes(offered)
          ? offered
          : PROTOCOL_VERSIONS[0];
      return answer({
        protocolVersion,
        capabilities: { tools: { listChanged: false } },
        serverInfo: { name: "smartman", title: "Smartman", version: "1" },
        instructions: INSTRUCTIONS,
      });
    }
    case "ping":
      return answer({});
    case "tools/list":
      return answer({ tools: TOOLS });
    case "tools/call": {
      const name = typeof params.name === "string" ? params.name : "";
      const store = {
        url: config.supabaseUrl,
        anonKey: config.anonKey,
        token: caller.token,
        userId: caller.userId,
        fetch: deps.fetch,
      };
      let result;
      try {
        result = await callTool(name, params.arguments, store, deps);
      } catch (error) {
        if (error instanceof SupabaseError) {
          return answer(
            {
              content: [{
                type: "text",
                text:
                  "Smartman's server did not answer. Nothing was changed by this call unless list_cards shows it; try again in a moment.",
              }],
              isError: true,
            },
            "unavailable",
            name,
          );
        }
        throw error;
      }
      return result.kind === "refused"
        ? answer(
          { content: [{ type: "text", text: result.message }], isError: true },
          "tool_refused",
          name,
        )
        : answer(
          {
            content: [{ type: "text", text: JSON.stringify(result.value) }],
            structuredContent: result.value,
          },
          "answered",
          name,
        );
    }
    default:
      return {
        response: Response.json(
          rpcError(id, -32601, `Method not found: ${method}`),
        ),
        entry: {
          user_id: caller.userId,
          method,
          tool: null,
          outcome: "not_found",
        },
      };
  }
}

function badRequest(
  userId: UserId,
  body: unknown,
  method: string | null = null,
): Exchange {
  return {
    response: Response.json(body, { status: 400 }),
    entry: { user_id: userId, method, tool: null, outcome: "bad_request" },
  };
}

function unavailable(
  userId: UserId | null,
  method: string | null,
  tool: string | null,
): Exchange {
  return {
    response: Response.json(
      rpcError(null, -32603, "Supabase Auth could not be reached"),
      {
        status: 503,
      },
    ),
    entry: { user_id: userId, method, tool, outcome: "unavailable" },
  };
}
