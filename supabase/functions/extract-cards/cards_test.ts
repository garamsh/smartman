import assert from "node:assert/strict";
import {
  cardsSchema,
  composeBack,
  KINDS,
  MAX_ANSWER_CHARS,
  MAX_CARDS,
  MAX_EXAMPLES,
  MAX_FIELD_CHARS,
  MAX_TOPIC_CHARS,
  parseCards,
  STEPS,
} from "./cards.ts";

const reply = (cards: unknown) => JSON.stringify({ cards });

/** A model's vocabulary card with no part of speech and no examples, overridden by `fields`. */
const item = (fields: Record<string, unknown> = {}) => ({
  kind: "vocabulary",
  front: "apple",
  answer: "사과",
  short: "사과",
  step: 1,
  topic: "과일",
  partOfSpeech: null,
  examples: [],
  ...fields,
});

/** A model's note card, overridden by `fields`. */
const note = (fields: Record<string, unknown> = {}) =>
  item({
    kind: "note",
    front: "연역 논증과 귀납 논증의 차이",
    answer:
      "연역은 전제가 참이면 결론이 반드시 참이고, 귀납은 결론이 개연적으로만 참이다.",
    short: "반드시 참과 개연적으로 참",
    step: 3,
    topic: "연역과 귀납",
    ...fields,
  });

Deno.test("parseCards returns a vocabulary card's fields trimmed, its answer as the meaning, and the composed back", () => {
  assert.deepEqual(
    parseCards(reply([item({
      front: "  run ",
      answer: "\n달리다, 운영하다\t",
      short: " 달리다 ",
      partOfSpeech: " [동] ",
      examples: [" I run every morning. ", "run a shop"],
    })])),
    [{
      kind: "vocabulary",
      front: "run",
      answer: "달리다, 운영하다",
      short: "달리다",
      step: 1,
      topic: "과일",
      examples: ["I run every morning.", "run a shop"],
      back: "[동] 달리다, 운영하다",
      meaning: "달리다, 운영하다",
      partOfSpeech: "[동]",
    }],
  );
});

Deno.test("a note card returns its concept, answers, step and topic, its back is the fullest answer, and it has no meaning", () => {
  const [card] = parseCards(reply([note({
    examples: ["253+4637+647898=652788 -> 연역"],
  })])) ?? [];
  assert.deepEqual(card, {
    kind: "note",
    front: "연역 논증과 귀납 논증의 차이",
    answer:
      "연역은 전제가 참이면 결론이 반드시 참이고, 귀납은 결론이 개연적으로만 참이다.",
    short: "반드시 참과 개연적으로 참",
    step: 3,
    topic: "연역과 귀납",
    examples: ["253+4637+647898=652788 -> 연역"],
    back:
      "연역은 전제가 참이면 결론이 반드시 참이고, 귀납은 결론이 개연적으로만 참이다.",
  });
  // An app that predates the shape takes back as the meaning when there is none.
  assert.ok(!Object.hasOwn(card, "meaning"), "no meaning key");
  assert.ok(!Object.hasOwn(card, "partOfSpeech"), "no partOfSpeech key");
});

Deno.test("a card without a part of speech or examples leaves both absent, and its back is the answer", () => {
  const [card] = parseCards(reply([item()])) ?? [];
  assert.equal(card.back, "사과");
  assert.equal(card.meaning, "사과");
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

Deno.test("parseCards takes each step from 1 to 5 and refuses any other", () => {
  for (const step of STEPS) {
    assert.equal(parseCards(reply([note({ step })]))?.[0].step, step);
  }
  for (const step of [0, 6, 2.5, "3", null]) {
    assert.equal(parseCards(reply([note({ step })])), null, String(step));
  }
});

Deno.test("parseCards takes each kind and refuses any other", () => {
  for (const kind of KINDS) {
    assert.equal(parseCards(reply([item({ kind })]))?.[0].kind, kind);
  }
  for (const kind of ["notes", "Vocabulary", null]) {
    assert.equal(parseCards(reply([item({ kind })])), null, String(kind));
  }
});

Deno.test("parseCards refuses a short form longer than the answer, and takes one as long", () => {
  assert.equal(
    parseCards(reply([note({ answer: "짧다", short: "더 길다" })])),
    null,
  );
  assert.equal(
    parseCards(reply([note({ answer: "같다", short: "같다" })]))?.[0].short,
    "같다",
    "control: a short form equal to the answer",
  );
});

Deno.test("parseCards refuses a note with a part of speech, which only vocabulary carries", () => {
  assert.equal(parseCards(reply([note({ partOfSpeech: "n." })])), null);
  assert.equal(
    parseCards(reply([item({ partOfSpeech: "n." })]))?.[0].partOfSpeech,
    "n.",
    "control: a vocabulary card with one",
  );
});

Deno.test("parseCards takes a topic trimmed, of 1 to 60 code points, and refuses any other", () => {
  const atLimit = "가".repeat(MAX_TOPIC_CHARS - 1) + "😀";
  assert.equal(
    parseCards(reply([note({ topic: "  3. 축약 " })]))?.[0].topic,
    "3. 축약",
  );
  assert.equal(
    parseCards(reply([note({ topic: atLimit })]))?.[0].topic,
    atLimit,
    "control: a topic of 60 code points",
  );
  for (const topic of [atLimit + "a", " ", "", 1, null]) {
    assert.equal(
      parseCards(reply([note({ topic })])),
      null,
      JSON.stringify(topic),
    );
  }
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
  assert.equal(parseCards(reply([item({ meaning: "사과" })])), null);
  // Prompt v2's shape, without kind, answer, short or step.
  assert.equal(
    parseCards(reply([{
      front: "apple",
      meaning: "사과",
      partOfSpeech: null,
      examples: [],
    }])),
    null,
  );
  const complete: Record<string, unknown> = item();
  for (const key of Object.keys(complete)) {
    const { [key]: _, ...missing } = complete;
    assert.equal(parseCards(reply([missing])), null, `without ${key}`);
  }
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
      { answer: "" },
      { short: " " },
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

Deno.test("parseCards refuses a field over its limit in code points, counting each emoji once", () => {
  const upTo = (n: number) => "가".repeat(n - 1) + "😀";
  const atLimit = upTo(MAX_FIELD_CHARS);
  assert.equal([...atLimit].length, 500);
  assert.equal(
    atLimit.length,
    501,
    "the field is longer than 500 UTF-16 units",
  );
  const long = upTo(MAX_ANSWER_CHARS);
  for (const name of ["front", "partOfSpeech"]) {
    assert.equal(
      parseCards(reply([item({ [name]: atLimit, answer: long })]))?.length,
      1,
      `${name} at the limit`,
    );
    assert.equal(
      parseCards(reply([item({ [name]: atLimit + "a", answer: long })])),
      null,
      `${name} over the limit`,
    );
  }
  assert.equal(
    parseCards(reply([item({ answer: long, short: atLimit })]))?.length,
    1,
    "an answer of 1000 and a short form of 500",
  );
  assert.equal(
    parseCards(reply([item({ answer: long + "a", short: atLimit })])),
    null,
    "an answer over 1000",
  );
  assert.equal(
    parseCards(reply([item({ answer: long, short: atLimit + "a" })])),
    null,
    "a short form over 500",
  );
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
      (_, i) => item({ front: `w${i}`, answer: `뜻${i}`, short: `뜻${i}` }),
    );
  assert.equal(parseCards(reply(cards(MAX_CARDS)))?.length, 100);
  assert.equal(parseCards(reply(cards(MAX_CARDS + 1))), null);
});

Deno.test("the schema sent to the model states the fields and the limits the parser enforces", () => {
  const cards = cardsSchema.properties.cards;
  const fields = cards.items.properties;
  assert.equal(cards.maxItems, MAX_CARDS);
  for (const field of [fields.front, fields.short, fields.partOfSpeech]) {
    assert.equal(field.minLength, 1);
    assert.equal(field.maxLength, MAX_FIELD_CHARS);
  }
  assert.equal(fields.answer.minLength, 1);
  assert.equal(fields.answer.maxLength, MAX_ANSWER_CHARS);
  assert.deepEqual(fields.kind.enum, ["vocabulary", "note"]);
  assert.deepEqual(fields.step.enum, [1, 2, 3, 4, 5]);
  assert.equal(fields.topic.type, "string");
  assert.equal(fields.topic.minLength, 1);
  assert.equal(fields.topic.maxLength, MAX_TOPIC_CHARS);
  assert.equal(fields.step.type, "integer");
  assert.deepEqual(fields.partOfSpeech.type, ["string", "null"]);
  assert.equal(fields.examples.maxItems, MAX_EXAMPLES);
  assert.equal(fields.examples.items.maxLength, MAX_FIELD_CHARS);
  assert.deepEqual(cards.items.required, [
    "kind",
    "front",
    "answer",
    "short",
    "step",
    "topic",
    "partOfSpeech",
    "examples",
  ]);
  assert.equal(cards.items.additionalProperties, false);
});
