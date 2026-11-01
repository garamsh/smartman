// The text that reads a page on, and the fronts it names.
import assert from "node:assert/strict";
import { continueAfter, lastFronts, MAX_NAMED_CHARS } from "./continuation.ts";

Deno.test("the follow-up names the cards read and the last fronts, and asks for an empty list when none come after", () => {
  const text = continueAfter(85, ["chat", "livre"]);
  assert.match(text, /^85 cards were already read/);
  assert.ok(text.includes(`"chat", "livre"`));
  assert.ok(
    text.endsWith(
      "When no entry comes after them, answer an empty card list.",
    ),
  );
});

Deno.test("the fronts named are the last that fit the characters a follow-up names", () => {
  const front = "x".repeat(1_000);
  const fronts = ["first", ...Array.from({ length: 4 }, () => front)];
  assert.deepEqual(lastFronts(fronts), fronts.slice(1));
  // Control: one character fewer a front leaves room for the first.
  const shorter = [
    "first",
    ...Array.from({ length: 4 }, () => "x".repeat(998)),
  ];
  assert.equal(4 * 998 + 5 <= MAX_NAMED_CHARS, true);
  assert.deepEqual(lastFronts(shorter), shorter);
});
