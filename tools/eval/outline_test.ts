// The outline call and the fill's outline, with OpenRouter replaced by a fake fetch.
import assert from "node:assert/strict";
import {
  modelId,
  OPENROUTER_URL,
} from "../../supabase/functions/extract-cards/openrouter.ts";
import { outline, outlineSchema, withOutline } from "./outline.ts";

const IMAGE = { type: "image/jpeg", base64: "AAAA" } as const;
const MODEL = modelId("vendor/dear");
if (MODEL === null) throw new Error("a valid model id");

/** A fetch answering every OpenRouter call with [content], recording each request body. */
function fake(content: unknown, status = 200) {
  const bodies: Record<string, unknown>[] = [];
  const fetch: typeof globalThis.fetch = (_input, init) => {
    bodies.push(JSON.parse(String(init?.body)));
    return Promise.resolve(Response.json({
      choices: [{ message: { content: JSON.stringify(content) } }],
      usage: { prompt_tokens: 900, completion_tokens: 30, cost: 0.002 },
    }, { status }));
  };
  return { fetch, bodies };
}

const deps = (fetch: typeof globalThis.fetch) => ({
  apiKey: "key",
  fetch,
  now: () => 0,
});

Deno.test("the outline call asks its model for the outline schema with the image, and returns the items and usage", async () => {
  const items = [{
    topic: "축약",
    name: "ㅗ + ㅏ 축약",
    gist: "ㅘ로 줄어든다",
  }];
  const { fetch, bodies } = fake({ items });
  const result = await outline(IMAGE, MODEL, deps(fetch));
  assert.deepEqual(result.items, items);
  assert.deepEqual(result.attempt.usage, {
    promptTokens: 900,
    completionTokens: 30,
    costUsd: 0.002,
  });
  const body = bodies[0] as {
    model: string;
    response_format: { json_schema: { name: string; schema: unknown } };
    messages: { role: string; content: unknown }[];
  };
  assert.equal(body.model, "vendor/dear");
  assert.equal(body.response_format.json_schema.name, "outline");
  assert.deepEqual(body.response_format.json_schema.schema, outlineSchema);
  assert.match(
    JSON.stringify(body.messages),
    /data:image\/jpeg;base64,AAAA/,
  );
});

Deno.test("an outline call that fails or answers other than an outline returns no items, with its usage", async () => {
  for (
    const [content, status] of [
      [{ items: [{ topic: "a", name: "b" }] }, 200],
      [{ cards: [] }, 200],
      [{ items: [] }, 500],
    ] as const
  ) {
    const result = await outline(
      IMAGE,
      MODEL,
      deps(fake(content, status).fetch),
    );
    assert.equal(result.items, null, JSON.stringify(content));
    assert.equal(result.attempt.usage?.costUsd, 0.002);
  }
  const control = await outline(IMAGE, MODEL, deps(fake({ items: [] }).fetch));
  assert.deepEqual(
    control.items,
    [],
    "control: an empty outline is an outline",
  );
});

Deno.test("the fill's outline goes into the user turn before the image, and only into OpenRouter calls", async () => {
  const seen: { url: string; body: string | undefined }[] = [];
  const send: typeof fetch = (input, init) => {
    seen.push({ url: String(input), body: init?.body as string | undefined });
    return Promise.resolve(new Response("{}"));
  };
  const outlined = withOutline(send, [
    { topic: "축약", name: "ㅗ + ㅏ 축약", gist: "ㅘ로 줄어든다" },
  ]);
  const request = {
    model: "vendor/cheap",
    messages: [
      { role: "system", content: "prompt" },
      {
        role: "user",
        content: [
          { type: "text", text: "Extract the cards from this photo." },
          {
            type: "image_url",
            image_url: { url: "data:image/jpeg;base64,AAAA" },
          },
        ],
      },
    ],
  };
  await outlined(OPENROUTER_URL, {
    method: "POST",
    body: JSON.stringify(request),
  });
  const sent = JSON.parse(seen[0].body ?? "");
  const user = sent.messages[1].content;
  assert.equal(user.length, 3);
  assert.equal(user[0].text, "Extract the cards from this photo.");
  assert.match(user[1].text, /- 축약 \/ ㅗ \+ ㅏ 축약: ㅘ로 줄어든다/);
  assert.match(user[1].text, /Take every card's text from the photo/);
  assert.equal(user[2].type, "image_url");
  assert.equal(
    sent.messages[0].content,
    "prompt",
    "the system prompt is the function's",
  );

  const other = JSON.stringify(request);
  await outlined("https://example.com/v1/chat/completions", { body: other });
  assert.equal(
    seen[1].body,
    other,
    "control: a request elsewhere is untouched",
  );
});
