// Prompt v9 (#261) is prompt v8 with one notes rule added: every card under a named rule holds the
// rule's name. Its text is what an admin saves in the prompt store (ADR 0073).
import assert from "node:assert/strict";
import { SYSTEM_PROMPT as V8 } from "./prompt_v8.ts";
import { PROMPT_VERSION, SYSTEM_PROMPT } from "./prompt_v9.ts";

/** The store's limit on a version's text (`20261019210000_prompts.sql`). */
const STORE_MAX_CHARS = 20000;

Deno.test("prompt v9 asks every card under a named rule to hold the rule's name in its front or answer", () => {
  assert.equal(PROMPT_VERSION, "v9");
  for (
    const phrase of [
      "The rule's name on every card under it",
      "every card made from them, a concept, cloze or identify card alike, holds that name in its front or in its answer",
      'such as the cloze front "축약: ㅗ+ㅏ -> ___" or the front "축약: ㅗ+ㅏ -> ㅘ", never "ㅗ+ㅏ -> ___" or "ㅗ+ㅏ -> ㅘ" alone',
    ]
  ) {
    assert.ok(SYSTEM_PROMPT.includes(phrase), phrase);
  }
  assert.ok(
    !V8.includes("The rule's name on every card under it"),
    "control: prompt v8 does not ask it",
  );
});

Deno.test("prompt v9 is prompt v8 with that one line added, every other line kept in order", () => {
  const v8 = V8.split("\n");
  const v9 = SYSTEM_PROMPT.split("\n");
  const added = v9.filter((line) => !v8.includes(line));
  assert.equal(added.length, 1);
  assert.ok(added[0].startsWith("  - The rule's name on every card under it:"));
  assert.deepEqual(v9.filter((line) => line !== added[0]), v8);
});

Deno.test("prompt v9 fits the prompt store, so an admin can save it as a version", () => {
  assert.ok(
    [...SYSTEM_PROMPT].length <= STORE_MAX_CHARS,
    `${[...SYSTEM_PROMPT].length} characters`,
  );
});
