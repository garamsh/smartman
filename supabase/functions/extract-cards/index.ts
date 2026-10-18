/** The extract-cards Edge Function: surveys one photo of a study page, and turns it into candidate cards. */

import { readConfig } from "./config.ts";
import { createHandler } from "./handler.ts";

Deno.serve(createHandler({
  config: readConfig((name) => Deno.env.get(name)),
  fetch,
  log: (entry) => console.log(JSON.stringify(entry)),
  now: () => performance.now(),
  clock: () => Date.now(),
}));
