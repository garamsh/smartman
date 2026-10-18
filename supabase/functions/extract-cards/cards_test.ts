import assert from "node:assert/strict";
import {
  cardsSchema,
  composeAnswer,
  composeBack,
  KINDS,
  MAX_ANSWER_CHARS,
  MAX_CARDS,
  MAX_EXAMPLES,
  MAX_EXTRAS,
  MAX_FIELD_CHARS,
  MAX_SENSES,
  MAX_TOPIC_CHARS,
  parseCards,
  TYPES,
} from "./cards.ts";

const reply = (cards: unknown) => JSON.stringify({ cards });

/** A model's vocabulary card of one sense with no part of speech, overridden by `fields`. */
const item = (fields: Record<string, unknown> = {}) => ({
  kind: "vocabulary",
  type: "concept",
  front: "apple",
  answer: null,
  topic: "과일",
  senses: [{ pos: null, meaning: "사과" }],
  extras: [],
  pronunciation: null,
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
    topic: "연역과 귀납",
    senses: [],
    ...fields,
  });

const one = (cards: unknown[]) => parseCards(reply(cards))?.[0];

Deno.test("parseCards returns a vocabulary card of one sense with its fields trimmed, its meaning and label as the answer and part of speech, and the composed back", () => {
  assert.deepEqual(
    one([item({
      front: "  run ",
      senses: [{ pos: " [동] ", meaning: "\n달리다, 운영하다\t" }],
      extras: [{ label: " 유의어 ", text: " sprint " }],
      pronunciation: " [rʌn] ",
      examples: [" I run every morning. ", "run a shop"],
    })]),
    {
      kind: "vocabulary",
      type: "concept",
      front: "run",
      answer: "달리다, 운영하다",
      short: "달리다, 운영하다",
      step: 1,
      topic: "과일",
      examples: ["I run every morning.", "run a shop"],
      back: "[동] 달리다, 운영하다",
      meaning: "달리다, 운영하다",
      partOfSpeech: "[동]",
      senses: [{ pos: "[동]", meaning: "달리다, 운영하다" }],
      extras: [{ label: "유의어", text: "sprint" }],
      pronunciation: "[rʌn]",
    },
  );
});

Deno.test("several senses keep their order and labels, and compose one line per sense with no part of speech, so an old app's back reads one sense per line", () => {
  const card = one([item({
    front: "face",
    senses: [
      { pos: "[동]", meaning: "직면하다, 마주하다" },
      { pos: "[명]", meaning: "표면, 겉면" },
      { pos: "[명]", meaning: "얼굴, 생김새" },
    ],
  })]);
  assert.ok(card?.kind === "vocabulary");
  assert.deepEqual(card.senses.map((sense) => sense.pos), [
    "[동]",
    "[명]",
    "[명]",
  ]);
  const lines = "[동] 직면하다, 마주하다\n[명] 표면, 겉면\n[명] 얼굴, 생김새";
  assert.equal(card.answer, lines);
  assert.equal(card.meaning, lines);
  assert.equal(card.back, lines, "not '[동] [명] [명] 직면하다, …'");
  assert.ok(!Object.hasOwn(card, "partOfSpeech"), "no single part of speech");
  // A sense without a label is its meaning alone on its line.
  assert.deepEqual(
    composeAnswer([{ pos: null, meaning: "a" }, { pos: "n.", meaning: "b" }]),
    { answer: "a\nn. b" },
  );
});

Deno.test("a note card returns its concept, answer and topic, its back is the fullest answer, and it has no meaning or senses", () => {
  const card = one([note({ examples: ["253+4637+647898=652788 -> 연역"] })]);
  assert.deepEqual(card, {
    kind: "note",
    type: "concept",
    front: "연역 논증과 귀납 논증의 차이",
    answer:
      "연역은 전제가 참이면 결론이 반드시 참이고, 귀납은 결론이 개연적으로만 참이다.",
    short:
      "연역은 전제가 참이면 결론이 반드시 참이고, 귀납은 결론이 개연적으로만 참이다.",
    step: 1,
    topic: "연역과 귀납",
    examples: ["253+4637+647898=652788 -> 연역"],
    back:
      "연역은 전제가 참이면 결론이 반드시 참이고, 귀납은 결론이 개연적으로만 참이다.",
  });
});

Deno.test("a vocabulary card without a label, extras, pronunciation or examples leaves those keys absent, and its back is the meaning", () => {
  const card = one([item()]);
  assert.equal(card?.back, "사과");
  for (const key of ["partOfSpeech", "extras", "pronunciation", "examples"]) {
    assert.ok(card !== undefined && !Object.hasOwn(card, key), `no ${key} key`);
  }
  const control = one([item({ senses: [{ pos: "n.", meaning: "사과" }] })]);
  assert.ok(control?.kind === "vocabulary");
  assert.equal(control.partOfSpeech, "n.", "control: a printed one is kept");
  assert.equal(control.back, "n. 사과");
});

Deno.test("composeBack puts the part of speech and a space before the meaning", () => {
  assert.equal(composeBack("먹다", "[동]"), "[동] 먹다");
  assert.equal(composeBack("먹다"), "먹다");
});

Deno.test("the model writes no short form or step, and each card carries its answer as the short form at step 1 for an app that reads them", () => {
  for (const card of [item(), note()]) {
    const parsed = one([card]);
    assert.equal(parsed?.short, parsed?.answer);
    assert.equal(parsed?.step, 1);
  }
  for (const extra of [{ short: "사과" }, { step: 1 }]) {
    assert.equal(
      parseCards(reply([item(extra)])),
      null,
      `prompt v4's ${Object.keys(extra)[0]} is not a key of the schema`,
    );
  }
});

Deno.test("parseCards takes each kind and refuses any other", () => {
  assert.equal(one([item()])?.kind, "vocabulary");
  assert.equal(one([note()])?.kind, "note");
  assert.deepEqual([...KINDS], ["vocabulary", "note"]);
  for (const kind of ["notes", "Vocabulary", null]) {
    assert.equal(parseCards(reply([item({ kind })])), null, String(kind));
  }
});

Deno.test("parseCards takes each type, concept, cloze or identify, and refuses any other or none", () => {
  for (const type of TYPES) {
    assert.equal(one([note({ type })])?.type, type);
  }
  for (const type of ["Concept", "judgment", "", null]) {
    assert.equal(parseCards(reply([note({ type })])), null, String(type));
  }
  const { type: _, ...untyped } = note();
  assert.equal(parseCards(reply([untyped])), null, "a card without a type");
});

Deno.test("a vocabulary card has senses and no answer, and a note an answer and no senses, extras or pronunciation", () => {
  assert.equal(parseCards(reply([item({ senses: [] })])), null, "no sense");
  assert.equal(
    parseCards(reply([item({ answer: "사과" })])),
    null,
    "an answer",
  );
  assert.equal(
    parseCards(reply([note({ answer: null })])),
    null,
    "no answer",
  );
  for (
    const fields of [
      { senses: [{ pos: null, meaning: "뜻" }] },
      { extras: [{ label: "유의어", text: "x" }] },
      { pronunciation: "[x]" },
    ]
  ) {
    assert.equal(
      parseCards(reply([note(fields)])),
      null,
      JSON.stringify(fields),
    );
  }
  assert.equal(
    parseCards(reply([item(), note()]))?.length,
    2,
    "control: each as its kind fills it",
  );
});

Deno.test("parseCards refuses prompt v5's vocabulary card, with its answer and part of speech and no senses", () => {
  assert.equal(
    parseCards(reply([{
      kind: "vocabulary",
      type: "concept",
      front: "apple",
      answer: "사과",
      topic: "과일",
      partOfSpeech: "n.",
      examples: [],
    }])),
    null,
  );
});

Deno.test("parseCards takes a topic trimmed, of 1 to 60 code points, and refuses any other", () => {
  const atLimit = "가".repeat(MAX_TOPIC_CHARS - 1) + "😀";
  assert.equal(one([note({ topic: "  3. 축약 " })])?.topic, "3. 축약");
  assert.equal(
    one([note({ topic: atLimit })])?.topic,
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
  for (const key of ["hint", "back", "meaning", "partOfSpeech"]) {
    assert.equal(parseCards(reply([item({ [key]: "x" })])), null, key);
  }
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
  for (
    const fields of [
      { front: 1 },
      { senses: "a" },
      { senses: [{ pos: null }] },
      { senses: [{ pos: 1, meaning: "뜻" }] },
      { senses: [{ pos: null, meaning: "뜻", note: "x" }] },
      { extras: [{ label: "유의어" }] },
      { extras: [{ label: "유의어", text: "x", more: "y" }] },
      { pronunciation: 1 },
      { examples: "a" },
      { examples: [1] },
    ]
  ) {
    assert.equal(
      parseCards(reply([item(fields)])),
      null,
      JSON.stringify(fields),
    );
  }
  assert.equal(parseCards(reply("a")), null);
  assert.equal(parseCards(reply([["a", "b"]])), null);
  assert.equal(parseCards("[]"), null);
});

Deno.test("parseCards refuses a field that is empty once trimmed", () => {
  for (
    const card of [
      item({ front: "  " }),
      note({ answer: "" }),
      item({ senses: [{ pos: " ", meaning: "사과" }] }),
      item({ senses: [{ pos: null, meaning: " " }] }),
      item({ extras: [{ label: " ", text: "x" }] }),
      item({ extras: [{ label: "유의어", text: "" }] }),
      item({ pronunciation: " " }),
      item({ examples: ["ok", " "] }),
    ]
  ) {
    assert.equal(parseCards(reply([card])), null, JSON.stringify(card));
  }
  assert.equal(
    one([item({ front: " a ", examples: [" b "] })])?.front,
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
  const fields = (text: string) => [
    { front: text },
    { senses: [{ pos: text, meaning: "뜻" }] },
    { senses: [{ pos: null, meaning: text }] },
    { extras: [{ label: text, text: "x" }] },
    { extras: [{ label: "유의어", text }] },
    { pronunciation: text },
    { examples: [text] },
  ];
  for (const field of fields(atLimit)) {
    assert.equal(
      parseCards(reply([item(field)]))?.length,
      1,
      `${JSON.stringify(field).slice(0, 30)} at the limit`,
    );
  }
  for (const field of fields(atLimit + "a")) {
    assert.equal(
      parseCards(reply([item(field)])),
      null,
      `${JSON.stringify(field).slice(0, 30)} over the limit`,
    );
  }
  const long = upTo(MAX_ANSWER_CHARS);
  assert.equal(
    parseCards(reply([note({ answer: long })]))?.length,
    1,
    "an answer of 1000",
  );
  assert.equal(
    parseCards(reply([note({ answer: long + "a" })])),
    null,
    "an answer over 1000",
  );
});

Deno.test("parseCards refuses more than 5 examples, 10 senses or 10 extras on a card", () => {
  const many = <T>(n: number, make: (i: number) => T) =>
    Array.from({ length: n }, (_, i) => make(i));
  const example = (i: number) => `e${i}`;
  const sense = (i: number) => ({ pos: null, meaning: `뜻${i}` });
  const extra = (i: number) => ({ label: "유의어", text: `x${i}` });
  assert.deepEqual(
    one([item({ examples: many(MAX_EXAMPLES, example) })])?.examples,
    many(5, example),
  );
  assert.equal(
    parseCards(reply([item({ examples: many(MAX_EXAMPLES + 1, example) })])),
    null,
  );
  assert.equal(
    parseCards(reply([item({ senses: many(MAX_SENSES, sense) })]))?.length,
    1,
  );
  assert.equal(
    parseCards(reply([item({ senses: many(MAX_SENSES + 1, sense) })])),
    null,
  );
  assert.equal(
    parseCards(reply([item({ extras: many(MAX_EXTRAS, extra) })]))?.length,
    1,
  );
  assert.equal(
    parseCards(reply([item({ extras: many(MAX_EXTRAS + 1, extra) })])),
    null,
  );
});

Deno.test("parseCards refuses more than 100 cards", () => {
  const cards = (n: number) =>
    Array.from({ length: n }, (_, i) => item({ front: `w${i}` }));
  assert.equal(parseCards(reply(cards(MAX_CARDS)))?.length, 100);
  assert.equal(parseCards(reply(cards(MAX_CARDS + 1))), null);
});

Deno.test("the schema sent to the model states the fields and the limits the parser enforces", () => {
  const cards = cardsSchema.properties.cards;
  const fields = cards.items.properties;
  assert.equal(cards.maxItems, MAX_CARDS);
  for (
    const field of [
      fields.front,
      fields.pronunciation,
      fields.senses.items.properties.meaning,
    ]
  ) {
    assert.equal(field.minLength, 1);
    assert.equal(field.maxLength, MAX_FIELD_CHARS);
  }
  assert.equal(fields.answer.maxLength, MAX_ANSWER_CHARS);
  assert.deepEqual(fields.answer.type, ["string", "null"]);
  assert.deepEqual(fields.pronunciation.type, ["string", "null"]);
  assert.deepEqual(fields.senses.items.properties.pos.type, ["string", "null"]);
  assert.deepEqual(fields.kind.enum, ["vocabulary", "note"]);
  assert.deepEqual(fields.type.enum, ["concept", "cloze", "identify"]);
  assert.equal(fields.topic.maxLength, MAX_TOPIC_CHARS);
  assert.equal(fields.senses.maxItems, MAX_SENSES);
  assert.deepEqual(fields.senses.items.required, ["pos", "meaning"]);
  assert.equal(fields.extras.maxItems, MAX_EXTRAS);
  assert.deepEqual(fields.extras.items.required, ["label", "text"]);
  assert.equal(fields.examples.maxItems, MAX_EXAMPLES);
  assert.equal(fields.examples.items.maxLength, MAX_FIELD_CHARS);
  const keys = [
    "kind",
    "type",
    "front",
    "answer",
    "topic",
    "senses",
    "extras",
    "pronunciation",
    "examples",
  ];
  assert.deepEqual(
    Object.keys(fields),
    keys,
    "no short form, step or part of speech",
  );
  assert.deepEqual(cards.items.required, keys);
  assert.equal(cards.items.additionalProperties, false);
  assert.equal(fields.senses.items.additionalProperties, false);
  assert.equal(fields.extras.items.additionalProperties, false);
});
