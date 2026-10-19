// The prompt store's seed (ADR 0073) is the prompt the function served before the store, so the
// deploy changes no user's prompt. deno.sh grants this file read access to that migration alone.
import assert from "node:assert/strict";
import { SYSTEM_PROMPT } from "./prompt_v8.ts";

const MIGRATION = "supabase/migrations/20261019210000_prompts.sql";

/** The text between the migration's `$prompt$` quotes. */
async function seededText(): Promise<string> {
  const sql = await Deno.readTextFile(MIGRATION);
  const parts = sql.split("$prompt$");
  assert.equal(parts.length, 3, "the migration quotes one text with $prompt$");
  return parts[1];
}

Deno.test("the migration seeds version 1 with prompt v8's text, character for character", async () => {
  const seeded = await seededText();
  assert.equal(seeded, SYSTEM_PROMPT);
  // Control: a one-character difference is not equal, so the comparison reads the whole text.
  assert.notEqual(seeded, SYSTEM_PROMPT.slice(0, -1));
});
