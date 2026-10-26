// The cost a model call is recorded at, from the usage OpenRouter's reply reports.
import assert from "node:assert/strict";
import {
  extractCards,
  type Extraction,
  type ModelId,
  modelId,
} from "./openrouter.ts";
import type { Image } from "./request.ts";

const MODEL = modelId("vendor/model") as ModelId;
const PHOTO: Image = { type: "image/png", base64: "AAAA" };
const CARD = {
  kind: "note",
  type: "concept",
  front: "연역 논증",
  answer: "전제가 참이면 결론이 반드시 참인 논증",
  topic: "연역과 귀납",
  senses: [],
  extras: [],
  pronunciation: null,
  examples: [],
  table: null,
  cloze: null,
};

/** One call answered with `body`, or with a failure when `status` is not 200. */
function extractWith(body: unknown, status = 200): Promise<Extraction> {
  return extractCards(PHOTO, {}, MODEL, "instructions", {
    apiKey: "key",
    now: () => 0,
    fetch: () => Promise.resolve(Response.json(body, { status })),
  });
}

const reply = (usage?: unknown) => ({
  choices: [{ message: { content: JSON.stringify({ cards: [CARD] }) } }],
  ...(usage === undefined ? {} : { usage }),
});

const costOf = async (usage?: unknown) =>
  (await extractWith(reply(usage))).attempts[0].usage?.costUsd;

Deno.test("a reply billed by OpenRouter records its cost", async () => {
  assert.equal(
    await costOf({ prompt_tokens: 1200, completion_tokens: 80, cost: 0.002 }),
    0.002,
  );
});

Deno.test("a BYOK reply records OpenRouter's cost plus the provider's upstream cost", async () => {
  const byok = {
    prompt_tokens: 1200,
    completion_tokens: 80,
    cost: 0,
    is_byok: true,
    cost_details: { upstream_inference_cost: 0.0023 },
  };
  assert.equal(await costOf(byok), 0.0023);
  assert.equal(
    await costOf({
      ...byok,
      cost: 0.0001,
      cost_details: { upstream_inference_cost: 0.0023 },
    }),
    0.0001 + 0.0023,
    "OpenRouter's own fee is kept beside the upstream price",
  );
});

Deno.test("cost details without an upstream cost leave the cost as reported", async () => {
  assert.equal(
    await costOf({
      prompt_tokens: 1,
      completion_tokens: 1,
      cost: 0.002,
      cost_details: {},
    }),
    0.002,
  );
});

Deno.test("a reply reporting no cost records none, and one without usage records no usage", async () => {
  assert.equal(await costOf({ prompt_tokens: 1, completion_tokens: 1 }), null);
  const failed = await extractWith({ error: { code: 503 } }, 503);
  assert.equal(failed.attempts[0].usage, null);
  const unreported = await extractWith(reply());
  assert.equal(unreported.attempts[0].usage, null);
  assert.equal(unreported.kind, "cards", "control: the reply itself is valid");
});
