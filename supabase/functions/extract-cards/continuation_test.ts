// The text that reads a page on, and the fronts it names.
import assert from "node:assert/strict";
import { askForMissing, lastFronts, MAX_NAMED_CHARS } from "./continuation.ts";

Deno.test("the follow-up names every front read and asks for every entry not among them, wherever it is, or an empty list", () => {
  assert.equal(
    askForMissing(2, ["chat", "livre"]),
    `2 cards were already read from this material, for the entries "chat", "livre". Answer with the cards of every entry of the material that is not in that list, wherever it is on the page, in the material's order, and no card for an entry in the list. When no entry is missing, answer an empty card list.`,
  );
  // Fronts too many to name are said to be the last ones read.
  assert.match(
    askForMissing(85, ["chat", "livre"]),
    /^85 cards were already read from this material, the last 2 for the entries "chat", "livre"\. /,
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
