// The handler end to end, with Supabase and OpenRouter replaced by a recording fake fetch.
// The suite runs without write or network permission, so a write anywhere fails the run.
import assert from "node:assert/strict";
import { readConfig } from "./config.ts";
import { createHandler, type LogEntry } from "./handler.ts";
import { OPENROUTER_URL } from "./openrouter.ts";
import { MAX_IMAGE_BYTES } from "./request.ts";

const SUPABASE_URL = "https://project.supabase.test";
const USER_ID = "00000000-0000-4000-8000-00000000000a";
const SIGNED_IN = "Bearer signed-in-token";
const OTHER_USER = "Bearer other-user-token";
/** The wall clock of a request, unless a test moves it. */
const NOON = Date.UTC(2026, 9, 18, 12);

const ENV: Record<string, string> = {
  SUPABASE_URL,
  SUPABASE_SERVICE_ROLE_KEY: "service-role-key",
  OPENROUTER_API_KEY: "openrouter-key",
  CARD_MODEL: "vendor/primary-model",
};

/** A model reply: the message text OpenRouter returns, or an HTTP failure. */
type Reply = { content: string } | { status: number };

const cardsReply = (cards: unknown): Reply => ({
  content: JSON.stringify({ cards }),
});

type Fake = {
  replies: Reply[];
  allowed: boolean;
  calls: { url: string; init: RequestInit | undefined }[];
};

function fakeFetch(fake: Fake): typeof fetch {
  return (input, init) => {
    const url = String(input);
    fake.calls.push({ url, init });
    if (url === `${SUPABASE_URL}/auth/v1/user`) {
      const authorization = new Headers(init?.headers).get("Authorization");
      if (authorization === SIGNED_IN) {
        return Promise.resolve(
          Response.json({ id: USER_ID, role: "authenticated" }),
        );
      }
      if (authorization === OTHER_USER) {
        return Promise.resolve(Response.json({
          id: "00000000-0000-4000-8000-00000000000b",
          role: "authenticated",
        }));
      }
      if (authorization === "Bearer anonymous-sign-in") {
        return Promise.resolve(
          Response.json({ id: USER_ID, is_anonymous: true }),
        );
      }
      return Promise.resolve(Response.json({ code: 403 }, { status: 403 }));
    }
    if (url === `${SUPABASE_URL}/rest/v1/rpc/consume_extraction`) {
      return Promise.resolve(Response.json(fake.allowed));
    }
    if (url === OPENROUTER_URL) {
      const reply = fake.replies.shift();
      if (reply === undefined) throw new Error("no scripted model reply left");
      if ("status" in reply) {
        return Promise.resolve(
          Response.json({ error: { code: reply.status } }, {
            status: reply.status,
          }),
        );
      }
      return Promise.resolve(Response.json({
        choices: [{ message: { role: "assistant", content: reply.content } }],
        usage: { prompt_tokens: 1200, completion_tokens: 80, cost: 0.002 },
      }));
    }
    throw new Error(`unexpected request to ${url}`);
  };
}

function encodeBase64(bytes: Uint8Array): string {
  let binary = "";
  for (let i = 0; i < bytes.length; i += 0x8000) {
    binary += String.fromCharCode(...bytes.subarray(i, i + 0x8000));
  }
  return btoa(binary);
}

/** An image of `size` bytes that opens with `head` and is filled with a marker pattern. */
function image(head: number[], size = 64): string {
  const bytes = new Uint8Array(size).map((_, i) => 0x41 + (i % 23));
  bytes.set(head);
  return encodeBase64(bytes);
}

const PNG = [0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a];
const JPEG = [0xff, 0xd8, 0xff, 0xe0];
const WEBP = [
  ...new TextEncoder().encode("RIFF"),
  0,
  0,
  0,
  0,
  ...new TextEncoder().encode("WEBP"),
];
const GIF = [...new TextEncoder().encode("GIF89a")];

/** The parts of an OpenRouter request body the tests read. */
type ModelCall = {
  model: string;
  messages: [
    { content: string },
    { content: [{ text: string }, { image_url: { url: string } }] },
  ];
  response_format: {
    type: string;
    json_schema: {
      strict: boolean;
      schema: {
        required: string[];
        properties: { cards: { items: { required: string[] } } };
      };
    };
  };
  provider: { require_parameters: boolean };
};

type Run = {
  status: number;
  body: Record<string, unknown>;
  logs: LogEntry[];
  console: string[];
  fake: Fake;
  modelCalls: ModelCall[];
};

async function run(
  options: {
    body?: unknown;
    rawBody?: string;
    authorization?: string | null;
    method?: string;
    replies?: Reply[];
    allowed?: boolean;
    env?: Record<string, string | undefined>;
    clock?: number;
  } = {},
): Promise<Run> {
  const fake: Fake = {
    replies: options.replies ?? [],
    allowed: options.allowed ?? true,
    calls: [],
  };
  const env = { ...ENV, ...options.env };
  const logs: LogEntry[] = [];
  const handler = createHandler({
    config: readConfig((name) => env[name]),
    fetch: fakeFetch(fake),
    log: (entry) => logs.push(entry),
    now: () => 0,
    clock: () => options.clock ?? NOON,
  });
  const headers = new Headers({ "Content-Type": "application/json" });
  const authorization = options.authorization === undefined
    ? SIGNED_IN
    : options.authorization;
  if (authorization !== null) headers.set("Authorization", authorization);
  const method = options.method ?? "POST";
  const request = new Request("https://functions.test/extract-cards", {
    method,
    headers,
    body: method === "POST"
      ? options.rawBody ?? JSON.stringify(options.body ?? { image: image(PNG) })
      : undefined,
  });

  const printed: string[] = [];
  const saved = { ...console };
  for (const level of ["log", "info", "warn", "error", "debug"] as const) {
    console[level] = (...args: unknown[]) =>
      printed.push(args.map(String).join(" "));
  }
  let response: Response;
  try {
    response = await handler(request);
  } finally {
    Object.assign(console, saved);
  }
  const modelCalls = fake.calls
    .filter((call) => call.url === OPENROUTER_URL)
    .map((call) => JSON.parse(String(call.init?.body)));
  return {
    status: response.status,
    body: await response.json(),
    logs,
    console: printed,
    fake,
    modelCalls,
  };
}

const usageCalls = (r: Run) =>
  r.fake.calls.filter((call) => call.url.endsWith("/rpc/consume_extraction"));
/**
 * Three cards as the model writes them: a vocabulary entry with a part of speech and an example,
 * one with neither, and a point of notes with the page's own example.
 */
const twoCards = [{
  kind: "vocabulary",
  front: "run",
  answer: "달리다",
  short: "달리다",
  step: 1,
  partOfSpeech: "[동]",
  examples: ["I run every morning."],
}, {
  kind: "vocabulary",
  front: "river",
  answer: "강",
  short: "강",
  step: 1,
  partOfSpeech: null,
  examples: [],
}, {
  kind: "note",
  front: "연역 논증이란?",
  answer: "전제가 참이면 결론이 반드시 참인 논증",
  short: "결론이 반드시 참",
  step: 2,
  partOfSpeech: null,
  examples: ["253+4637+647898=652788 -> 연역"],
}];
/** The same cards as the function answers them. */
const twoAnswered = [{
  kind: "vocabulary",
  front: "run",
  answer: "달리다",
  short: "달리다",
  step: 1,
  examples: ["I run every morning."],
  back: "[동] 달리다",
  meaning: "달리다",
  partOfSpeech: "[동]",
}, {
  kind: "vocabulary",
  front: "river",
  answer: "강",
  short: "강",
  step: 1,
  back: "강",
  meaning: "강",
}, {
  kind: "note",
  front: "연역 논증이란?",
  answer: "전제가 참이면 결론이 반드시 참인 논증",
  short: "결론이 반드시 참",
  step: 2,
  examples: ["253+4637+647898=652788 -> 연역"],
  back: "전제가 참이면 결론이 반드시 참인 논증",
}];

Deno.test("the suite runs without write or network permission", () => {
  assert.notEqual(
    Deno.permissions.querySync({ name: "write" }).state,
    "granted",
  );
  assert.notEqual(Deno.permissions.querySync({ name: "net" }).state, "granted");
});

Deno.test("a signed-in user's photo returns each card's kind, answers, step and back, and a vocabulary card's fields", async () => {
  const r = await run({ replies: [cardsReply(twoCards)] });
  assert.equal(r.status, 200);
  assert.deepEqual(r.body, { cards: twoAnswered });
  const [, river, note] = r.body.cards as Record<string, unknown>[];
  assert.ok(
    !Object.hasOwn(river, "partOfSpeech") && !Object.hasOwn(river, "examples"),
    "a card without a part of speech or examples carries neither key",
  );
  // An app that reads only front and back, or takes back as the meaning without one, shows
  // a note card's fullest answer.
  assert.ok(!Object.hasOwn(note, "meaning"), "a note card carries no meaning");
  assert.equal(note.back, note.answer);
  assert.equal(r.modelCalls.length, 1);
  assert.equal(r.modelCalls[0].model, "vendor/primary-model");
});

Deno.test("a request without a signed-in user is refused with 401 before any usage or model call", async () => {
  for (
    const authorization of [
      null,
      "Bearer anon-key",
      "Bearer anonymous-sign-in",
      "Basic x",
    ]
  ) {
    const r = await run({ authorization, replies: [cardsReply(twoCards)] });
    assert.equal(r.status, 401, `authorization ${authorization}`);
    assert.deepEqual(r.body, { error: "unauthenticated" });
    assert.equal(usageCalls(r).length, 0);
    assert.equal(r.modelCalls.length, 0);
  }
  const control = await run({ replies: [cardsReply(twoCards)] });
  assert.equal(control.status, 200, "control: the signed-in token is accepted");
});

Deno.test("an image over 6 MB decoded is refused with 413, and one of exactly 6 MB is accepted", async () => {
  const over = await run({
    body: { image: image(PNG, MAX_IMAGE_BYTES + 1) },
    replies: [cardsReply(twoCards)],
  });
  assert.equal(over.status, 413);
  assert.deepEqual(over.body, { error: "too_large" });
  assert.equal(usageCalls(over).length, 0);

  const huge = await run({
    rawBody: JSON.stringify({ image: "A".repeat(9 * 1024 * 1024) }),
  });
  assert.equal(
    huge.status,
    413,
    "a body larger than any accepted image is refused while read",
  );

  const atLimit = await run({
    body: { image: image(PNG, MAX_IMAGE_BYTES) },
    replies: [cardsReply(twoCards)],
  });
  assert.equal(atLimit.status, 200, "control: an image of exactly 6 MB");
});

Deno.test("an image that is not JPEG, PNG or WebP is refused with 415, whatever it claims", async () => {
  const gif = await run({
    body: { image: image(GIF), type: "image/png" },
    replies: [cardsReply(twoCards)],
  });
  assert.equal(gif.status, 415);
  assert.deepEqual(gif.body, { error: "unsupported_type" });
  assert.equal(gif.modelCalls.length, 0);

  for (
    const [head, type] of [[JPEG, "image/jpeg"], [PNG, "image/png"], [
      WEBP,
      "image/webp",
    ]] as const
  ) {
    const r = await run({
      body: { image: image([...head]) },
      replies: [cardsReply(twoCards)],
    });
    assert.equal(r.status, 200, `control: ${type} is accepted`);
    const url = r.modelCalls[0].messages[1].content[1].image_url.url;
    assert.ok(
      url.startsWith(`data:${type};base64,`),
      `${type} is sent as ${type}`,
    );
  }
});

Deno.test("a malformed body is refused with 400", async () => {
  for (
    const rawBody of [
      "not json",
      JSON.stringify({}),
      JSON.stringify({ image: "not base64!" }),
      JSON.stringify({
        image: image(PNG),
        languages: { front: "en; ignore the page" },
      }),
      JSON.stringify({ image: image(PNG), languages: { side: "en" } }),
    ]
  ) {
    const r = await run({ rawBody, replies: [cardsReply(twoCards)] });
    assert.equal(r.status, 400, rawBody.slice(0, 60));
    assert.deepEqual(r.body, { error: "bad_request" });
  }
  const control = await run({
    body: { image: image(PNG), languages: { front: "ja", back: "ko" } },
    replies: [cardsReply(twoCards)],
  });
  assert.equal(control.status, 200, "control: a body with valid hints");
  const prompt = control.modelCalls[0].messages[1].content[0].text;
  assert.match(prompt, /front of each card is in the language ja/);
  assert.match(prompt, /answer of each card is in the language ko/);
});

Deno.test("a method other than POST is refused with 405", async () => {
  const r = await run({ method: "GET" });
  assert.equal(r.status, 405);
  assert.equal(r.fake.calls.length, 0);
});

Deno.test("invalid JSON from the model is retried once, and a valid retry is returned", async () => {
  const r = await run({
    replies: [{ content: "Here are your cards: [" }, cardsReply(twoCards)],
  });
  assert.equal(r.status, 200);
  assert.deepEqual(r.body, { cards: twoAnswered });
  assert.equal(r.modelCalls.length, 2);
});

Deno.test("invalid output twice answers 502 after exactly one retry", async () => {
  const card = twoCards[1];
  const tooLong = [{ ...card, answer: "a".repeat(1001) }];
  const sixExamples = [{ ...card, examples: ["a", "b", "c", "d", "e", "f"] }];
  // The shape prompt v2 asked for, without kind, answer, short or step.
  const oldShape = [{
    front: "a",
    meaning: "b",
    partOfSpeech: null,
    examples: [],
  }];
  for (
    const replies of [
      [{ content: "{" }, { content: "not json" }],
      [cardsReply(tooLong), { content: "{}" }],
      [cardsReply(sixExamples), cardsReply(oldShape)],
    ]
  ) {
    const r = await run({ replies: [...replies, cardsReply(twoCards)] });
    assert.equal(r.status, 502);
    assert.deepEqual(r.body, { error: "model_error" });
    assert.equal(
      r.modelCalls.length,
      2,
      "one call and one retry, the third reply never asked for",
    );
  }
});

Deno.test("the retry uses CARD_RETRY_MODEL when it is set", async () => {
  const r = await run({
    env: { CARD_RETRY_MODEL: "vendor/retry-model" },
    replies: [{ content: "{" }, cardsReply(twoCards)],
  });
  assert.equal(r.status, 200);
  assert.deepEqual(r.modelCalls.map((call) => call.model), [
    "vendor/primary-model",
    "vendor/retry-model",
  ]);
});

Deno.test("a model HTTP error answers 502 without a retry", async () => {
  const r = await run({ replies: [{ status: 500 }, cardsReply(twoCards)] });
  assert.equal(r.status, 502);
  assert.deepEqual(r.body, { error: "model_error" });
  assert.equal(r.modelCalls.length, 1);
});

Deno.test("a photo with no cards answers 422", async () => {
  const r = await run({ replies: [cardsReply([])] });
  assert.equal(r.status, 422);
  assert.deepEqual(r.body, { error: "no_cards" });
});

Deno.test("the model call asks for the cards schema from providers that honour it", async () => {
  const r = await run({ replies: [cardsReply(twoCards)] });
  const call = r.modelCalls[0];
  assert.equal(call.response_format.type, "json_schema");
  assert.equal(call.response_format.json_schema.strict, true);
  assert.deepEqual(call.response_format.json_schema.schema.required, ["cards"]);
  assert.deepEqual(
    call.response_format.json_schema.schema.properties.cards.items.required,
    ["kind", "front", "answer", "short", "step", "partOfSpeech", "examples"],
  );
  assert.equal(call.provider.require_parameters, true);
});

Deno.test("a user over the daily limit is refused with 429 and no model call", async () => {
  const refused = await run({
    allowed: false,
    replies: [cardsReply(twoCards)],
  });
  assert.equal(refused.status, 429);
  assert.deepEqual(refused.body, { error: "rate_limited" });
  assert.equal(refused.modelCalls.length, 0);

  const allowed = await run({ allowed: true, replies: [cardsReply(twoCards)] });
  assert.equal(
    allowed.status,
    200,
    "control: the same request while under the limit",
  );
  const usage = usageCalls(allowed);
  assert.equal(usage.length, 1);
  assert.deepEqual(JSON.parse(String(usage[0].init?.body)), {
    user_id: USER_ID,
    daily_limit: 30,
  });
  const headers = new Headers(usage[0].init?.headers);
  assert.equal(
    headers.get("Authorization"),
    "Bearer service-role-key",
    "recorded with the service role",
  );
});

Deno.test("a missing OpenRouter key or model answers 503", async () => {
  for (
    const env of [
      { OPENROUTER_API_KEY: undefined },
      { OPENROUTER_API_KEY: " " },
      { CARD_MODEL: undefined },
      { CARD_RETRY_MODEL: "not a model id" },
      { SURVEY_MODEL: "not a model id" },
      { VOCAB_MODEL: "not a model id" },
    ]
  ) {
    const r = await run({ env, replies: [cardsReply(twoCards)] });
    assert.equal(r.status, 503, JSON.stringify(env));
    assert.deepEqual(r.body, { error: "not_configured" });
    assert.equal(r.fake.calls.length, 0);
  }
  const control = await run({ replies: [cardsReply(twoCards)] });
  assert.equal(control.status, 200, "control: the full configuration");
});

Deno.test("each request logs one line of the allowed fields and never the image", async () => {
  const photo = image(PNG, 4096);
  const outcomes = [
    await run({ body: { image: photo }, replies: [cardsReply(twoCards)] }),
    await run({
      body: { image: photo },
      replies: [{ content: "{" }, { content: "{" }],
    }),
    await run({ body: { image: photo }, replies: [{ status: 503 }] }),
    await run({ body: { image: photo }, allowed: false }),
    await run({ body: { image: photo }, authorization: null }),
  ];
  for (const r of outcomes) {
    assert.equal(r.logs.length, 1);
    assert.deepEqual(Object.keys(r.logs[0]).sort(), [
      "completion_tokens",
      "latency_ms",
      "model",
      "outcome",
      "prompt_tokens",
      "user_id",
    ]);
    assert.ok(!JSON.stringify(r.logs).includes(photo.slice(0, 64)));
    assert.deepEqual(r.console, [], "nothing else is printed");
    for (const call of r.fake.calls.filter((c) => c.url !== OPENROUTER_URL)) {
      assert.ok(
        !String(call.init?.body ?? "").includes(photo.slice(0, 64)),
        `the image is not sent to ${call.url}`,
      );
    }
  }
  assert.ok(
    JSON.stringify(outcomes[0].modelCalls).includes(photo),
    "control: the image is in the model request, so the search above would find it",
  );
  assert.deepEqual(outcomes.map((r) => r.logs[0].outcome), [
    "ok",
    "model_error",
    "model_error",
    "rate_limited",
    "unauthenticated",
  ]);
  assert.deepEqual(outcomes[0].logs[0], {
    user_id: USER_ID,
    model: "vendor/primary-model",
    latency_ms: 0,
    prompt_tokens: 1200,
    completion_tokens: 80,
    outcome: "ok",
  });
  assert.equal(
    outcomes[1].logs[0].prompt_tokens,
    2400,
    "tokens are summed over the retry",
  );
  assert.equal(outcomes[4].logs[0].user_id, null);
});

// The photo conversation of ADR 0057: a survey, then cards made to the user's plan.

/** A survey reply: a page of notes with a group of rules and a group of examples. */
const notesSurvey = {
  summary: "한국어 문법 노트예요",
  groups: [{
    id: "rules",
    kind: "note",
    title: "축약·탈락",
    count: 8,
    memorise: true,
    sample: "오+아라 -> 와라",
    example: { question: "오 + 아라 = ?", answer: "와라" },
  }, {
    id: "date",
    kind: "note",
    title: "수업 날짜",
    count: 1,
    memorise: false,
    sample: "10월 18일",
    example: { question: "수업 날짜는?", answer: "10월 18일" },
  }],
};
/** A survey reply: a page of vocabulary alone. */
const vocabularySurvey = {
  summary: "English vocabulary list",
  groups: [{
    id: "words",
    kind: "vocabulary",
    title: "Words",
    count: 15,
    memorise: true,
    sample: "run 달리다",
    example: { question: "run", answer: "달리다" },
  }],
};
const surveyReply = (survey: unknown): Reply => ({
  content: JSON.stringify(survey),
});
const plan = {
  groups: [{
    id: "rules",
    title: "축약·탈락",
    shape: { front: "term", back: "answer" },
  }],
};

/** Surveys `photo` and returns the conversation token the survey answered with. */
async function conversationFor(
  photo: string,
  survey: unknown = notesSurvey,
): Promise<string> {
  const r = await run({
    body: { image: photo, survey: true },
    replies: [surveyReply(survey)],
  });
  assert.equal(r.status, 200, "the survey succeeded");
  return r.body.conversation as string;
}

Deno.test("a survey answers the page's summary, its groups and a conversation, and counts one extraction", async () => {
  const r = await run({
    body: { image: image(PNG), survey: true },
    replies: [surveyReply(notesSurvey)],
  });
  assert.equal(r.status, 200);
  assert.equal(r.body.summary, notesSurvey.summary);
  assert.deepEqual(r.body.groups, notesSurvey.groups);
  assert.equal(typeof r.body.conversation, "string");
  assert.equal(r.body.cards, undefined, "no card yet");
  assert.equal(usageCalls(r).length, 1);
  const call = r.modelCalls[0];
  assert.match(call.messages[0].content, /You make no cards\./);
  assert.equal(
    (call.response_format.json_schema as { name?: string }).name,
    "survey",
  );
});

Deno.test("the survey runs on SURVEY_MODEL, and on CARD_MODEL when it is unset", async () => {
  const set = await run({
    body: { image: image(PNG), survey: true },
    replies: [surveyReply(notesSurvey)],
    env: { SURVEY_MODEL: "vendor/fast-model" },
  });
  assert.deepEqual(set.modelCalls.map((call) => call.model), [
    "vendor/fast-model",
  ]);
  const unset = await run({
    body: { image: image(PNG), survey: true },
    replies: [surveyReply(notesSurvey)],
  });
  assert.deepEqual(unset.modelCalls.map((call) => call.model), [
    "vendor/primary-model",
  ]);
});

Deno.test("a survey with no group answers 422, and invalid output twice 502 after one retry on the survey model", async () => {
  const empty = await run({
    body: { image: image(PNG), survey: true },
    replies: [surveyReply({ summary: "빈 페이지", groups: [] })],
  });
  assert.equal(empty.status, 422);
  assert.deepEqual(empty.body, { error: "no_cards" });
  const invalid = await run({
    body: { image: image(PNG), survey: true },
    replies: [
      surveyReply({ summary: "x" }),
      surveyReply({
        ...notesSurvey,
        groups: [notesSurvey.groups[0], notesSurvey.groups[0]],
      }),
    ],
    env: { SURVEY_MODEL: "vendor/fast-model" },
  });
  assert.equal(invalid.status, 502);
  assert.deepEqual(invalid.modelCalls.map((call) => call.model), [
    "vendor/fast-model",
    "vendor/fast-model",
  ]);
});

Deno.test("cards made on the surveyed photo with its token count nothing more, and any other token counts as usual", async () => {
  const photo = image(PNG);
  const token = await conversationFor(photo);
  const make = (
    options: {
      token?: string;
      photo?: string;
      clock?: number;
      authorization?: string;
    },
  ) =>
    run({
      body: {
        image: options.photo ?? photo,
        plan,
        ...(options.token === undefined ? {} : { conversation: options.token }),
      },
      replies: [cardsReply(twoCards)],
      clock: options.clock,
      authorization: options.authorization,
    });

  const counted = async (
    options: Parameters<typeof make>[0],
    reason: string,
  ) => {
    const r = await make(options);
    assert.equal(r.status, 200, reason);
    return usageCalls(r).length;
  };
  // Control: the same photo and user, before the token expires.
  assert.equal(await counted({ token, clock: NOON + 29 * 60_000 }, "same"), 0);
  assert.equal(await counted({}, "no token"), 1);
  assert.equal(
    await counted({ token, photo: image(PNG, 65) }, "another photo"),
    1,
  );
  assert.equal(
    await counted({ token, clock: NOON + 31 * 60_000 }, "expired"),
    1,
  );
  assert.equal(
    await counted({ token, authorization: OTHER_USER }, "another user"),
    1,
  );
  const [body, signature] = token.split(".");
  const forged = `${body}.${signature.slice(0, -2)}${
    signature.endsWith("AA") ? "BB" : "AA"
  }`;
  assert.equal(await counted({ token: forged }, "forged"), 1);
  assert.equal(await counted({ token: "not-a-token" }, "malformed"), 1);
});

Deno.test("a plan's groups and typed topics are put to the model, each in its shape, and today's call has none", async () => {
  const planned = await run({
    body: {
      image: image(PNG),
      plan: { ...plan, added: ["불규칙 활용"] },
    },
    replies: [cardsReply(twoCards)],
  });
  assert.equal(planned.status, 200);
  assert.deepEqual(planned.body, { cards: twoAnswered });
  const text = planned.modelCalls[0].messages[1].content[0].text;
  assert.match(text, /Make cards only for the groups below/);
  assert.match(
    text,
    /- "축약·탈락" \(rules\): "front" is the item's term, formula or example alone, as the page writes it; "answer" is the full answer the page gives/,
  );
  assert.match(text, /- "불규칙 활용", a topic the learner asked for/);
  // Control: without a plan, the model is asked for every card, as before.
  const today = await run({ replies: [cardsReply(twoCards)] });
  assert.doesNotMatch(
    today.modelCalls[0].messages[1].content[0].text,
    /Make cards only/,
  );
});

Deno.test("a page of vocabulary alone is made on VOCAB_MODEL; notes, a typed topic, or no token keep CARD_MODEL", async () => {
  const env = { VOCAB_MODEL: "vendor/cheap-model" };
  const photo = image(PNG);
  const vocabularyToken = await conversationFor(photo, vocabularySurvey);
  const notesToken = await conversationFor(photo, notesSurvey);
  const modelOf = async (body: Record<string, unknown>) => {
    const r = await run({
      body: { image: photo, ...body },
      replies: [cardsReply(twoCards)],
      env,
    });
    assert.equal(r.status, 200);
    return r.modelCalls[0].model;
  };
  const words = {
    groups: [{
      id: "words",
      title: "Words",
      shape: { front: "question", back: "short" },
    }],
  };
  assert.equal(
    await modelOf({ plan: words, conversation: vocabularyToken }),
    "vendor/cheap-model",
  );
  assert.equal(
    await modelOf({ plan: words, conversation: notesToken }),
    "vendor/primary-model",
    "a page with notes",
  );
  assert.equal(
    await modelOf({
      plan: { ...words, added: ["phrasal verbs"] },
      conversation: vocabularyToken,
    }),
    "vendor/primary-model",
    "a typed topic",
  );
  assert.equal(
    await modelOf({ plan: words }),
    "vendor/primary-model",
    "no token",
  );
  // The retry stays on the card models.
  const retried = await run({
    body: { image: photo, plan: words, conversation: vocabularyToken },
    replies: [{ content: "not json" }, cardsReply(twoCards)],
    env: { ...env, CARD_RETRY_MODEL: "vendor/strong-model" },
  });
  assert.deepEqual(retried.modelCalls.map((call) => call.model), [
    "vendor/cheap-model",
    "vendor/strong-model",
  ]);
});

Deno.test("a survey with a plan, or a malformed plan or conversation, is refused with 400 before any count", async () => {
  const group = plan.groups[0];
  for (
    const extra of [
      { survey: true, plan },
      { survey: false },
      { plan: { groups: [] } },
      {
        plan: {
          groups: [{ ...group, shape: { front: "side", back: "short" } }],
        },
      },
      { plan: { groups: [{ ...group, title: "" }] } },
      { plan: { groups: [{ ...group, id: "x".repeat(41) }] } },
      { plan: { groups: [group], added: ["a", "b", "c", "d", "e", "f"] } },
      { plan: { groups: Array.from({ length: 13 }, () => group) } },
      { plan, conversation: 7 },
      { plan, conversation: "" },
    ]
  ) {
    const r = await run({
      body: { image: image(PNG), ...extra },
      replies: [cardsReply(twoCards)],
    });
    assert.equal(r.status, 400, JSON.stringify(extra));
    assert.equal(usageCalls(r).length, 0);
  }
  const control = await run({
    body: { image: image(PNG), plan: { groups: [], added: ["불규칙 활용"] } },
    replies: [cardsReply(twoCards)],
  });
  assert.equal(control.status, 200, "control: a typed topic alone is a plan");
});
