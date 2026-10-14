/** The extract-cards Edge Function: turns one photo of a vocabulary page into candidate cards. */

import { readConfig } from "./config.ts";
import { createHandler } from "./handler.ts";

Deno.serve(createHandler({
  config: readConfig((name) => Deno.env.get(name)),
  fetch,
  log: (entry) => console.log(JSON.stringify(entry)),
  now: () => performance.now(),
}));
