import assert from "node:assert/strict";
import {
  cardsSchema,
  composeBack,
  MAX_CARDS,
  MAX_EXAMPLES,
  MAX_FIELD_CHARS,
  parseCards,
} from "./cards.ts";

const reply = (cards: unknown) => JSON.stringify({ cards });

/** A model card with no part of speech and no examples, overridden by `fields`. */
const item = (fields: Record<string, unknown> = {}) => ({
  front: "apple",
  meaning: "사과",
  partOfSpeech: null,
  examples: [],
  ...fields,
});

Deno.test("parseCards returns every field trimmed, with the composed back", () => {
  assert.deepEqual(
    parseCards(reply([item({
      front: "  run ",
      meaning: "\n달리다\t",
      partOfSpeech: " [동] ",
      examples: [" I run every morning. ", "run a shop"],
    })])),
    [{
      front: "run",
      back: "[동] 달리다",
      meaning: "달리다",
      partOfSpeech: "[동]",
      examples: ["I run every morning.", "run a shop"],
    }],
  );
});

Deno.test("a card without a part of speech or examples leaves both absent, and its back is the meaning", () => {
  const [card] = parseCards(reply([item()])) ?? [];
  assert.deepEqual(card, { front: "apple", back: "사과", meaning: "사과" });
  assert.ok(!Object.hasOwn(card, "partOfSpeech"), "no partOfSpeech key");
  assert.ok(!Object.hasOwn(card, "examples"), "no examples key");
  const [control] = parseCards(reply([item({ partOfSpeech: "n." })])) ?? [];
  assert.equal(control.partOfSpeech, "n.", "control: a printed one is kept");
  assert.equal(control.back, "n. 사과");
});

Deno.test("composeBack puts the part of speech and a space before the meaning", () => {
  assert.equal(composeBack("먹다", "[동]"), "[동] 먹다");
  assert.equal(composeBack("먹다"), "먹다");
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
  assert.equal(parseCards(reply([item()]))?.length, 1, "control: a valid card");
  assert.equal(
    parseCards(JSON.stringify({ cards: [item()], note: "x" })),
    null,
  );
  assert.equal(parseCards(reply([item({ hint: "x" })])), null);
  assert.equal(parseCards(reply([item({ back: "사과" })])), null);
  assert.equal(parseCards(reply([{ front: "apple", back: "사과" }])), null);
  const { examples: _, ...noExamples } = item();
  assert.equal(parseCards(reply([noExamples])), null);
  const { partOfSpeech: __, ...noPartOfSpeech } = item();
  assert.equal(parseCards(reply([noPartOfSpeech])), null);
  assert.equal(parseCards(reply([item({ front: 1 })])), null);
  assert.equal(parseCards(reply([item({ partOfSpeech: 1 })])), null);
  assert.equal(parseCards(reply([item({ examples: "a" })])), null);
  assert.equal(parseCards(reply([item({ examples: [1] })])), null);
  assert.equal(parseCards(reply("a")), null);
  assert.equal(parseCards(reply([["a", "b"]])), null);
  assert.equal(parseCards("[]"), null);
});

Deno.test("parseCards refuses a field that is empty once trimmed", () => {
  for (
    const fields of [
      { front: "  " },
      { meaning: "" },
      { partOfSpeech: " " },
      { examples: ["ok", " "] },
    ]
  ) {
    assert.equal(
      parseCards(reply([item(fields)])),
      null,
      JSON.stringify(fields),
    );
  }
  assert.equal(
    parseCards(reply([item({ front: " a ", examples: [" b "] })]))?.[0].front,
    "a",
    "control: fields with text inside the whitespace",
  );
});

Deno.test("parseCards refuses a field over 500 code points, counting each emoji once", () => {
  const atLimit = "가".repeat(MAX_FIELD_CHARS - 1) + "😀";
  assert.equal([...atLimit].length, 500);
  assert.equal(
    atLimit.length,
    501,
    "the field is longer than 500 UTF-16 units",
  );
  for (const name of ["front", "meaning", "partOfSpeech"]) {
    assert.equal(
      parseCards(reply([item({ [name]: atLimit })]))?.length,
      1,
      `${name} at the limit`,
    );
    assert.equal(
      parseCards(reply([item({ [name]: atLimit + "a" })])),
      null,
      `${name} over the limit`,
    );
  }
  assert.equal(parseCards(reply([item({ examples: [atLimit] })]))?.length, 1);
  assert.equal(parseCards(reply([item({ examples: [atLimit + "a"] })])), null);
});

Deno.test("parseCards refuses more than 5 examples on a card", () => {
  const examples = (n: number) => Array.from({ length: n }, (_, i) => `e${i}`);
  assert.deepEqual(
    parseCards(reply([item({ examples: examples(MAX_EXAMPLES) })]))?.[0]
      .examples,
    examples(5),
  );
  assert.equal(
    parseCards(reply([item({ examples: examples(MAX_EXAMPLES + 1) })])),
    null,
  );
});

Deno.test("parseCards refuses more than 100 cards", () => {
  const cards = (n: number) =>
    Array.from(
      { length: n },
      (_, i) => item({ front: `w${i}`, meaning: `뜻${i}` }),
    );
  assert.equal(parseCards(reply(cards(MAX_CARDS)))?.length, 100);
  assert.equal(parseCards(reply(cards(MAX_CARDS + 1))), null);
});

Deno.test("the schema sent to the model states the fields and the limits the parser enforces", () => {
  const cards = cardsSchema.properties.cards;
  const fields = cards.items.properties;
  assert.equal(cards.maxItems, MAX_CARDS);
  for (const field of [fields.front, fields.meaning, fields.partOfSpeech]) {
    assert.equal(field.minLength, 1);
    assert.equal(field.maxLength, MAX_FIELD_CHARS);
  }
  assert.deepEqual(fields.partOfSpeech.type, ["string", "null"]);
  assert.equal(fields.examples.maxItems, MAX_EXAMPLES);
  assert.equal(fields.examples.items.maxLength, MAX_FIELD_CHARS);
  assert.deepEqual(cards.items.required, [
    "front",
    "meaning",
    "partOfSpeech",
    "examples",
  ]);
  assert.equal(cards.items.additionalProperties, false);
});
