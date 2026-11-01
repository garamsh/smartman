// The ways of reading a dense page the eval measures (ADR 0135), with OpenRouter replaced by a fake.
import assert from "node:assert/strict";
import {
  CARD_RULES,
  OUTPUT_CONTRACT,
  parseReply,
} from "../../supabase/functions/extract-cards/cards.ts";
import { RETRY_START_LIMIT_MS } from "../../supabase/functions/extract-cards/handler.ts";
import {
  MAX_OUTPUT_TOKENS,
  type ModelId,
  modelId,
} from "../../supabase/functions/extract-cards/openrouter.ts";
import {
  ALTERNATIVES,
  continueAfter,
  extractContinuing,
  HIGHER_CAP_TOKENS,
  LEAN_CONTRACT,
  LEAN_FIELDS_RULE,
  leanSchema,
  parseLeanReply,
} from "./dense.ts";

const MODEL = modelId("vendor/model") as ModelId;
const PHOTO = { type: "image/png", base64: "AAAA" } as const;

/** A vocabulary card in the card list's full shape. */
const full = (front: string, meaning: string) => ({
  kind: "vocabulary",
  type: "concept",
  front,
  answer: null,
  topic: "단어 101-200",
  senses: [{ labels: [], meaning, examples: [] }],
  extras: [],
  pronunciation: null,
  examples: [],
  table: null,
  cloze: null,
});

/** The same card in the lean shape: no field left at its default. */
const lean = (front: string, meaning: string) => ({
  kind: "vocabulary",
  front,
  topic: "단어 101-200",
  senses: [{ meaning }],
});

type Sent = { body: Record<string, unknown> };

/** A fetch answering each chat call with the next of [replies], recording what was sent. */
function fake(
  replies: { text: string; finish: string }[],
  sent: Sent[],
  clock?: { now: number; perCall: number },
): typeof fetch {
  return (_input, init) => {
    sent.push({ body: JSON.parse(String(init?.body)) });
    if (clock !== undefined) clock.now += clock.perCall;
    const reply = replies.shift();
    if (reply === undefined) throw new Error("no scripted reply left");
    return Promise.resolve(Response.json({
      choices: [{
        finish_reason: reply.finish,
        message: { content: reply.text },
      }],
      usage: { prompt_tokens: 100, completion_tokens: 10, cost: 0.001 },
    }));
  };
}

const deps = (send: typeof fetch, now = () => 0) => ({
  apiKey: "key",
  fetch: send,
  now,
  timeoutMs: 1000,
});

/** A reply of [cards] cut partway into one more card. */
const cut = (cards: unknown[]) => ({
  text: JSON.stringify({ cards: [...cards, full("x", "y")] }).slice(0, -30),
  finish: "length",
});
const whole = (cards: unknown[]) => ({
  text: JSON.stringify({ cards }),
  finish: "stop",
});

Deno.test("a lean reply is read as the full card list it stands for, by the same rules", () => {
  const leanCards = parseLeanReply(
    JSON.stringify({
      cards: [lean("maison", "집"), lean("tomber", "넘어지다")],
    }),
  );
  const fullCards = parseReply(
    JSON.stringify({
      cards: [full("maison", "집"), full("tomber", "넘어지다")],
    }),
  );
  assert.deepEqual(leanCards, fullCards);
  assert.equal(leanCards?.cards.length, 2);
  // A lean card that breaks a rule is dropped by that rule.
  const broken = parseLeanReply(
    JSON.stringify({
      cards: [
        { ...lean("maison", "집"), answer: "집" },
        lean("chat", "고양이"),
      ],
    }),
  );
  assert.deepEqual(broken?.dropped, ["vocabulary_answer"]);
  // Control: a reply that is not the envelope is refused.
  assert.equal(parseLeanReply(JSON.stringify([lean("a", "b")])), null);
});

Deno.test("the lean schema requires only a card's kind, front and topic and a sense's meaning, and its contract says so", () => {
  const card = leanSchema.properties.cards.items;
  assert.deepEqual(card.required, ["kind", "front", "topic"]);
  assert.deepEqual(card.properties.senses.items.required, ["meaning"]);
  assert.ok(LEAN_CONTRACT.includes(LEAN_FIELDS_RULE));
  assert.ok(!LEAN_CONTRACT.includes(CARD_RULES.fields));
  // Control: the function's own contract keeps every field required.
  assert.ok(OUTPUT_CONTRACT.includes(CARD_RULES.fields));
});

Deno.test("each way sends its own reply form and cap", async () => {
  const caps = new Map<string, unknown>();
  for (const alternative of ALTERNATIVES) {
    const sent: Sent[] = [];
    await alternative.extract(
      PHOTO,
      {},
      MODEL,
      "prompt",
      deps(fake([whole([full("chat", "고양이")])], sent)),
    );
    caps.set(alternative.label, sent[0].body.max_tokens);
  }
  assert.deepEqual(Object.fromEntries(caps), {
    today: MAX_OUTPUT_TOKENS,
    lean: MAX_OUTPUT_TOKENS,
    cap: HIGHER_CAP_TOKENS,
    continue: MAX_OUTPUT_TOKENS,
  });
  const leanSent: Sent[] = [];
  await ALTERNATIVES[1].extract(
    PHOTO,
    {},
    MODEL,
    "prompt",
    deps(fake([whole([lean("chat", "고양이")])], leanSent)),
  );
  const format = leanSent[0].body.response_format as {
    json_schema: { schema: unknown };
  };
  assert.deepEqual(format.json_schema.schema, leanSchema);
});

Deno.test("a cut reply is continued once after its last card, and the cards read twice are kept once", async () => {
  const sent: Sent[] = [];
  const extraction = await extractContinuing(
    PHOTO,
    {},
    MODEL,
    "prompt",
    deps(
      fake([
        cut([full("maison", "집"), full("chat", "고양이")]),
        whole([full("chat", "고양이"), full("livre", "책")]),
      ], sent),
    ),
  );
  assert.equal(extraction.kind, "cards");
  if (extraction.kind !== "cards") return;
  assert.deepEqual(extraction.cards.map((card) => card.front), [
    "maison",
    "chat",
    "livre",
  ]);
  assert.equal(extraction.cut, false);
  assert.equal(extraction.attempts.length, 2);
  assert.ok(
    JSON.stringify(sent[1].body.messages).includes(
      JSON.stringify(continueAfter("chat", 2)).slice(1, -1),
    ),
    "the second call asks for the entries after the last one read",
  );
  // Control: a whole first reply is answered after one call.
  const once: Sent[] = [];
  const answered = await extractContinuing(
    PHOTO,
    {},
    MODEL,
    "prompt",
    deps(fake([whole([full("maison", "집")])], once)),
  );
  assert.equal(answered.kind, "cards");
  assert.equal(once.length, 1);
});

Deno.test("a cut reply that ended past the retry limit is not continued", async () => {
  const late: Sent[] = [];
  const clock = { now: 0, perCall: RETRY_START_LIMIT_MS };
  const extraction = await extractContinuing(
    PHOTO,
    {},
    MODEL,
    "prompt",
    deps(
      fake([cut([full("maison", "집")]), whole([])], late, clock),
      () => clock.now,
    ),
  );
  assert.equal(late.length, 1);
  assert.equal(extraction.kind === "cards" && extraction.cut, true);
  // Control: the same reply a millisecond sooner is continued.
  const early: Sent[] = [];
  const sooner = { now: 0, perCall: RETRY_START_LIMIT_MS - 1 };
  await extractContinuing(
    PHOTO,
    {},
    MODEL,
    "prompt",
    deps(
      fake(
        [cut([full("maison", "집")]), whole([full("chat", "고양이")])],
        early,
        sooner,
      ),
      () => sooner.now,
    ),
  );
  assert.equal(early.length, 2);
});
