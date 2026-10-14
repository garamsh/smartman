import assert from "node:assert/strict";
import { cardsSchema, MAX_CARDS, MAX_SIDE_CHARS, parseCards } from "./cards.ts";

const reply = (cards: unknown) => JSON.stringify({ cards });

Deno.test("parseCards returns the cards with each side trimmed", () => {
  assert.deepEqual(
    parseCards(reply([{ front: "  apple ", back: "\n사과\t" }])),
    [{ front: "apple", back: "사과" }],
  );
});

Deno.test("parseCards accepts an empty list, which the handler reports as no cards", () => {
  assert.deepEqual(parseCards(reply([])), []);
});

Deno.test("parseCards refuses a reply that is not JSON", () => {
  assert.equal(parseCards('{"cards": ['), null);
  assert.equal(parseCards("```json\n" + reply([]) + "\n```"), null);
  assert.deepEqual(
    parseCards(reply([])),
    [],
    "control: the same list as bare JSON",
  );
});

Deno.test("parseCards refuses keys and types the schema does not allow", () => {
  const card = { front: "a", back: "b" };
  assert.deepEqual(parseCards(reply([card])), [card], "control: a valid card");
  assert.equal(parseCards(JSON.stringify({ cards: [card], note: "x" })), null);
  assert.equal(parseCards(reply([{ ...card, hint: "x" }])), null);
  assert.equal(parseCards(reply([{ front: "a" }])), null);
  assert.equal(parseCards(reply([{ front: 1, back: "b" }])), null);
  assert.equal(parseCards(reply("a")), null);
  assert.equal(parseCards(reply([["a", "b"]])), null);
  assert.equal(parseCards("[]"), null);
});

Deno.test("parseCards refuses a side that is empty once trimmed", () => {
  assert.equal(parseCards(reply([{ front: "  ", back: "b" }])), null);
  assert.deepEqual(parseCards(reply([{ front: " a ", back: "b" }])), [{
    front: "a",
    back: "b",
  }], "control: a side with text inside the whitespace");
});

Deno.test("parseCards refuses a side over 500 code points, counting each emoji once", () => {
  const atLimit = "가".repeat(MAX_SIDE_CHARS - 1) + "😀";
  assert.equal([...atLimit].length, 500);
  assert.equal(atLimit.length, 501, "the side is longer than 500 UTF-16 units");
  assert.deepEqual(parseCards(reply([{ front: atLimit, back: "b" }])), [{
    front: atLimit,
    back: "b",
  }]);
  assert.equal(parseCards(reply([{ front: "a", back: atLimit + "a" }])), null);
});

Deno.test("parseCards refuses more than 100 cards", () => {
  const cards = (n: number) =>
    Array.from({ length: n }, (_, i) => ({ front: `w${i}`, back: `뜻${i}` }));
  assert.equal(parseCards(reply(cards(MAX_CARDS)))?.length, 100);
  assert.equal(parseCards(reply(cards(MAX_CARDS + 1))), null);
});

Deno.test("the schema sent to the model states the limits the parser enforces", () => {
  const items = cardsSchema.properties.cards;
  assert.equal(items.maxItems, MAX_CARDS);
  assert.equal(items.items.properties.front.maxLength, MAX_SIDE_CHARS);
  assert.equal(items.items.properties.back.maxLength, MAX_SIDE_CHARS);
  assert.deepEqual(items.items.required, ["front", "back"]);
  assert.equal(items.items.additionalProperties, false);
});
