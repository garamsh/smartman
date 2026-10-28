// Prompt v10 (#474) is prompt v9 taking what to memorise from the page's content alone, never from
// a learner's marks, and choosing each item's form after identifying the items. Its text is what an
// admin saves in the prompt store (ADR 0073).
import assert from "node:assert/strict";
import { SYSTEM_PROMPT as V9 } from "./prompt_v9.ts";
import { PROMPT_VERSION, SYSTEM_PROMPT } from "./prompt_v10.ts";

/** The store's limit on a version's text (`20261019210000_prompts.sql`). */
const STORE_MAX_CHARS = 20000;

const CONTENT_RULE = "- What to memorise comes from the page's content:";
const MARKS_RULE = "- A learner's marks are not content:";
const TWO_STEPS_RULE = "- Work in two steps.";
const HANDWRITING_FIRST = "  - Handwriting first:";

Deno.test("prompt v10 takes what to memorise from the page's content and never makes a card of a learner's mark or note", () => {
  assert.equal(PROMPT_VERSION, "v10");
  for (
    const phrase of [
      `${CONTENT_RULE} its printed text, or, on a page written by hand throughout, such as handwritten lecture notes, its handwritten lines.`,
      "notes, tips or translations written by hand in the margins, between the lines or in another ink over a printed page",
      'Never make a card of a mark or a handwritten note, never take any field\'s text from one, and never start a front with "★" or another mark.',
      "A line of the content that the learner marked is carded like every other line, in the words the page prints.",
      "A mark may only put the line it marks ahead of unmarked ones when the page holds more than 100 cards; it never adds an item the content does not hold, and never drops one it does.",
    ]
  ) {
    assert.ok(SYSTEM_PROMPT.includes(phrase), phrase);
  }
  assert.ok(!SYSTEM_PROMPT.includes(HANDWRITING_FIRST));
  assert.ok(!SYSTEM_PROMPT.includes("handwritten tips"));
  assert.ok(!SYSTEM_PROMPT.includes('its front starting with "★ "'));
  assert.ok(
    V9.includes(HANDWRITING_FIRST) && V9.includes("handwritten tips") &&
      V9.includes('its front starting with "★ "') && !V9.includes(MARKS_RULE),
    "control: prompt v9 asks a card of every handwritten note and keeps it first",
  );
});

Deno.test("prompt v10 identifies the page's items before it chooses each item's form", () => {
  const identify = SYSTEM_PROMPT.indexOf(
    "First identify every item on the page worth memorising, in the page's order: each definition, rule, member of a list, case or condition under a rule, exception, vocabulary entry, and cell of a comparison or classification table.",
  );
  const choose = SYSTEM_PROMPT.indexOf(
    'Then choose for each item the form a learner recalls it best in: "concept" for a named term, definition, rule or exception; "cloze" for a list line or a sentence recalled in context; "table" for a table whose cells are to be memorised; and a vocabulary card for an entry',
  );
  assert.ok(identify > 0, "identifies the items");
  assert.ok(choose > identify, "then chooses each item's form");
  assert.ok(!V9.includes(TWO_STEPS_RULE), "control: prompt v9 does not ask it");
});

Deno.test("prompt v10 is prompt v9 with its three rules added, the handwriting rule dropped and the cap's order reworded, every other line kept in order", () => {
  const v9 = V9.split("\n");
  const v10 = SYSTEM_PROMPT.split("\n");
  const added = v10.filter((line) => !v9.includes(line));
  const dropped = v9.filter((line) => !v10.includes(line));
  assert.equal(added.length, 4);
  [CONTENT_RULE, MARKS_RULE, TWO_STEPS_RULE, "Answer with JSON only"].forEach(
    (start, i) => assert.ok(added[i].startsWith(start), start),
  );
  assert.equal(dropped.length, 2);
  assert.ok(dropped[0].startsWith(HANDWRITING_FIRST));
  assert.ok(dropped[1].startsWith("Answer with JSON only"));
  // One fact per card, the rule's name on sub-points, examples only from the page and nothing
  // invented are v9's lines, kept as they were.
  for (
    const kept of [
      "  - One card per fact:",
      "  - The rule's name on every card under it:",
      "- Examples come only from the page:",
      "- Every fact in an answer comes from the page.",
    ]
  ) {
    assert.ok(v10.some((line) => line.startsWith(kept)), kept);
  }
  assert.deepEqual(
    v10.filter((line) => !added.includes(line)),
    v9.filter((line) => !dropped.includes(line)),
  );
});

Deno.test("prompt v10 fits the prompt store, so an admin can save it as a version", () => {
  assert.ok(
    [...SYSTEM_PROMPT].length <= STORE_MAX_CHARS,
    `${[...SYSTEM_PROMPT].length} characters`,
  );
});
