/** The mcp Edge Function: knowno's remote MCP server for Claude and ChatGPT (ADR 0126). */

import { readConfig } from "./config.ts";
import { createHandler } from "./handler.ts";

Deno.serve(createHandler({
  config: readConfig((name) => Deno.env.get(name)),
  fetch,
  log: (entry) => console.log(JSON.stringify(entry)),
  now: () => Date.now(),
  random: (bytes) => crypto.getRandomValues(new Uint8Array(bytes)),
}));
