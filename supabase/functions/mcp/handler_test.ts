// The MCP server end to end, with Supabase Auth and PostgREST replaced by an in-memory fake that
// applies row-level security's owner rule. The suite runs without write or network permission.
import assert from "node:assert/strict";
import type { IdSource } from "./cards.ts";
import { readConfig } from "./config.ts";
import { createHandler, type LogEntry } from "./handler.ts";

const SUPABASE_URL = "http://kong:8000";
const ANON_KEY = "anon-key";
const ADA = "00000000-0000-4000-8000-00000000000a";
const GRACE = "00000000-0000-4000-8000-00000000000b";
const ADA_DECK = "00000000-0000-7000-8000-0000000000d1";
const ADA_OTHER_DECK = "00000000-0000-7000-8000-0000000000d2";
const ADA_DELETED_DECK = "00000000-0000-7000-8000-0000000000d3";
const GRACE_PUBLIC_DECK = "00000000-0000-7000-8000-0000000000e1";

/** A JWT whose payload holds [claims]; the fake Auth server decides whether it is valid. */
function jwt(claims: Record<string, unknown>): string {
  const part = (value: unknown) =>
    btoa(JSON.stringify(value)).replace(/=+$/, "").replace(/\+/g, "-").replace(
      /\//g,
      "_",
    );
  return `${part({ alg: "ES256" })}.${part(claims)}.signature`;
}

const ADA_TOKEN = jwt({ sub: ADA, client_id: "claude", aud: "authenticated" });
const GRACE_TOKEN = jwt({
  sub: GRACE,
  client_id: "chatgpt",
  aud: "authenticated",
});
/** A session the web or the phone holds: Auth accepts it, and it carries no client_id. */
const ADA_SESSION = jwt({ sub: ADA, aud: "authenticated" });
const EXPIRED = jwt({ sub: ADA, client_id: "claude", exp: 1 });

type Row = Record<string, unknown>;

type Fake = {
  decks: Row[];
  cards: Row[];
  /** "offline" makes every request to PostgREST fail to arrive. */
  rest: "up" | "offline";
  calls: { url: string; method: string; headers: Headers }[];
};

function block(type: string, payload: Row) {
  return { type, v: 1, id: crypto.randomUUID(), payload };
}

function card(
  id: string,
  deck: string,
  user: string,
  front: unknown[],
  back: unknown[],
  extra = {},
) {
  return {
    id,
    deck_id: deck,
    user_id: user,
    front,
    back,
    card_key: String(
      (front[0] as { payload: { text?: string } }).payload.text ?? "",
    ).toLowerCase(),
    deleted_at: null,
    created_at: `2026-10-0${id.slice(-1)}T00:00:00.000Z`,
    ...extra,
  };
}

function seed(): Fake {
  return {
    rest: "up",
    calls: [],
    decks: [
      {
        id: ADA_DECK,
        user_id: ADA,
        name: "영단어",
        visibility: "private",
        deleted_at: null,
        created_at: "2026-10-01",
      },
      {
        id: ADA_OTHER_DECK,
        user_id: ADA,
        name: "Biology",
        visibility: "private",
        deleted_at: null,
        created_at: "2026-10-02",
      },
      {
        id: ADA_DELETED_DECK,
        user_id: ADA,
        name: "Gone",
        visibility: "private",
        deleted_at: "2026-10-03",
        created_at: "2026-10-03",
      },
      {
        id: GRACE_PUBLIC_DECK,
        user_id: GRACE,
        name: "Grace's",
        visibility: "public",
        deleted_at: null,
        created_at: "2026-10-01",
      },
    ],
    cards: [
      card("00000000-0000-7000-8000-000000000c01", ADA_DECK, ADA, [
        block("text", { text: "apple" }),
      ], [
        block("senses", {
          senses: [{
            labels: [{ kind: "part_of_speech", category: "noun", text: "명" }],
            meaning: "사과",
            examples: ["An apple a day."],
          }],
        }),
      ]),
      card("00000000-0000-7000-8000-000000000c02", ADA_DECK, ADA, [
        block("text", { text: "Banana" }),
      ], [
        block("text", { text: "바나나" }),
      ]),
      card(
        "00000000-0000-7000-8000-000000000c03",
        ADA_DECK,
        ADA,
        [block("cloze", { text: "The ___ is red", answers: ["cherry"] })],
        [block("text", { text: "stale back" })],
        { card_key: "the cherry is red" },
      ),
      card(
        "00000000-0000-7000-8000-000000000c04",
        ADA_DECK,
        ADA,
        [block("text", { text: "deleted" })],
        [],
        {
          deleted_at: "2026-10-05",
        },
      ),
      card("00000000-0000-7000-8000-000000000c05", ADA_OTHER_DECK, ADA, [
        block("text", { text: "cell" }),
      ], [
        block("text", { text: "세포 apple" }),
      ]),
      card("00000000-0000-7000-8000-000000000c06", GRACE_PUBLIC_DECK, GRACE, [
        block("text", { text: "apple pie" }),
      ], [
        block("text", { text: "grace's" }),
      ]),
    ],
  };
}

/** The user a token signs in, as Supabase Auth answers `/auth/v1/user`. */
function authUser(token: string | undefined): string | null {
  if (token === ADA_TOKEN || token === ADA_SESSION) return ADA;
  if (token === GRACE_TOKEN) return GRACE;
  return null;
}

/** A filter PostgREST reads from the query: `column=eq.value` and `column=is.null`. */
function matches(row: Row, params: URLSearchParams, prefix = ""): boolean {
  for (const [key, value] of params) {
    if (
      !key.startsWith(prefix) ||
      ["select", "order", "limit", "offset"].includes(key)
    ) continue;
    const column = key.slice(prefix.length);
    if (column.includes(".")) continue;
    if (value === "is.null" && row[column] !== null) return false;
    if (value.startsWith("eq.") && String(row[column]) !== value.slice(3)) {
      return false;
    }
  }
  return true;
}

/** PostgREST over [fake], with row-level security's rules for [user]. */
function rest(
  fake: Fake,
  url: URL,
  method: string,
  headers: Headers,
  body: unknown,
) {
  const user = authUser(headers.get("Authorization")?.slice(7));
  if (user === null || headers.get("apikey") !== ANON_KEY) {
    return Response.json({ code: "PGRST301" }, { status: 401 });
  }
  const table = url.pathname.split("/").at(-1);
  const rows = table === "decks"
    ? fake.decks
    : table === "cards"
    ? fake.cards
    : null;
  if (rows === null) return Response.json({}, { status: 404 });
  if (method === "POST") {
    const inserted = body as Row[];
    for (const row of inserted) {
      // The insert policy, and the composite foreign key from a card to its owner's deck.
      if (row.user_id !== user) {
        return Response.json({ code: "42501" }, { status: 403 });
      }
      if (
        table === "cards" &&
        !fake.decks.some((deck) =>
          deck.id === row.deck_id && deck.user_id === user
        )
      ) return Response.json({ code: "23503" }, { status: 409 });
    }
    rows.push(...inserted.map((row) => ({ deleted_at: null, ...row })));
    return new Response(null, { status: 201 });
  }
  // The select policy: the user's own rows, and a visibly public deck and its live cards.
  const visible = rows.filter((row) =>
    row.user_id === user ||
    (table === "decks"
      ? row.visibility === "public" && row.deleted_at === null
      : fake.decks.some((deck) =>
        deck.id === row.deck_id && deck.visibility === "public" &&
        deck.deleted_at === null
      ))
  );
  const params = url.searchParams;
  let found = visible.filter((row) => matches(row, params));
  // `order=created_at.asc,id.asc`, the order every listing names.
  found.sort((a, b) =>
    String(a.created_at).localeCompare(String(b.created_at)) ||
    String(a.id).localeCompare(String(b.id))
  );
  const total = found.length;
  const offset = Number(params.get("offset") ?? 0);
  const limit = Number(params.get("limit") ?? 1000);
  found = found.slice(offset, offset + limit);
  const select = params.get("select") ?? "";
  const shaped = found.map((row) => {
    const out: Row = {};
    for (const column of select.split(",")) {
      if (column === "cards(count)") {
        out.cards = [{
          count: fake.cards.filter((c) =>
            c.deck_id === row.id && matches(c, params, "cards.")
          )
            .length,
        }];
      } else out[column] = row[column];
    }
    return out;
  });
  const range = headers.get("Prefer") === "count=exact"
    ? { "Content-Range": `${offset}-${offset + shaped.length - 1}/${total}` }
    : undefined;
  return Response.json(shaped, { headers: range });
}

function fakeFetch(fake: Fake): typeof fetch {
  return async (input, init) => {
    const url = new URL(String(input));
    const method = init?.method ?? "GET";
    const headers = new Headers(init?.headers);
    fake.calls.push({ url: url.href, method, headers });
    if (url.href === `${SUPABASE_URL}/auth/v1/user`) {
      const user = authUser(headers.get("Authorization")?.slice(7));
      return user === null
        ? Response.json({ code: 403, error_code: "bad_jwt" }, { status: 403 })
        : Response.json({ id: user, role: "authenticated" });
    }
    if (url.href.startsWith(`${SUPABASE_URL}/rest/v1/`)) {
      if (fake.rest === "offline") throw new TypeError("error sending request");
      const body = typeof init?.body === "string"
        ? JSON.parse(init.body)
        : undefined;
      return await rest(fake, url, method, headers, body);
    }
    throw new Error(`unexpected request to ${url.href}`);
  };
}

type Run = {
  status: number;
  headers: Headers;
  json: unknown;
  logs: LogEntry[];
  fake: Fake;
};

let clock = Date.UTC(2026, 9, 29);

async function send(
  options: {
    token?: string | null;
    method?: string;
    path?: string;
    body?: unknown;
    headers?: Record<string, string>;
    fake?: Fake;
    ids?: IdSource;
    supabaseUrl?: string;
  } = {},
): Promise<Run> {
  const fake = options.fake ?? seed();
  const logs: LogEntry[] = [];
  const handler = createHandler({
    config: readConfig((name) =>
      ({
        SUPABASE_URL: options.supabaseUrl ?? SUPABASE_URL,
        SUPABASE_ANON_KEY: ANON_KEY,
      })[name]
    ),
    fetch: fakeFetch(fake),
    log: (entry) => logs.push(entry),
    ...(options.ids ?? {
      now: () => clock++,
      random: (bytes: number) => crypto.getRandomValues(new Uint8Array(bytes)),
    }),
  });
  const headers = new Headers({
    "X-Forwarded-Host": "127.0.0.1:54321",
    "Content-Type": "application/json",
    ...options.headers,
  });
  const token = options.token === undefined ? ADA_TOKEN : options.token;
  if (token !== null) headers.set("Authorization", `Bearer ${token}`);
  const method = options.method ?? "POST";
  const response = await handler(
    new Request(`http://localhost:9000${options.path ?? "/mcp"}`, {
      method,
      headers,
      body: method === "POST" ? JSON.stringify(options.body ?? {}) : undefined,
    }),
  );
  const text = await response.text();
  return {
    status: response.status,
    headers: response.headers,
    json: text === "" ? null : JSON.parse(text),
    logs,
    fake,
  };
}

/** Calls the tool [name] and returns its result object. */
async function call(
  name: string,
  args: unknown,
  fake = seed(),
  token: string = ADA_TOKEN,
  ids?: IdSource,
) {
  const run = await send({
    token,
    fake,
    ids,
    body: {
      jsonrpc: "2.0",
      id: 7,
      method: "tools/call",
      params: { name, arguments: args },
    },
  });
  assert.equal(run.status, 200);
  const { result } = run.json as {
    result: {
      isError?: boolean;
      structuredContent?: Row;
      content: { text: string }[];
    };
  };
  return { result, fake, logs: run.logs };
}

const METADATA = `${SUPABASE_URL}/functions/v1/mcp/oauth-protected-resource`;
/** A hosted project's `SUPABASE_URL`. */
const PROJECT = "https://abcdefghijklmnopqrst.supabase.co";

Deno.test("a request without a token is answered 401 with the resource metadata's address, and one with a connector's token is served", async () => {
  const missing = await send({
    token: null,
    body: { jsonrpc: "2.0", id: 1, method: "ping" },
  });
  assert.equal(missing.status, 401);
  assert.equal(
    missing.headers.get("WWW-Authenticate"),
    `Bearer resource_metadata="${METADATA}"`,
  );
  const served = await send({
    body: { jsonrpc: "2.0", id: 1, method: "ping" },
  });
  assert.equal(served.status, 200);
  assert.deepEqual(served.json, { jsonrpc: "2.0", id: 1, result: {} });
});

Deno.test("an expired token is answered 401 with invalid_token and the resource metadata", async () => {
  const run = await send({
    token: EXPIRED,
    body: { jsonrpc: "2.0", id: 1, method: "ping" },
  });
  assert.equal(run.status, 401);
  const challenge = run.headers.get("WWW-Authenticate") ?? "";
  assert.match(
    challenge,
    /^Bearer error="invalid_token", error_description="[^"]+"/,
  );
  assert.match(challenge, new RegExp(`resource_metadata="${METADATA}"$`));
  assert.equal(run.fake.calls[0]?.url, `${SUPABASE_URL}/auth/v1/user`);
  assert.equal(run.fake.calls[0]?.headers.get("apikey"), ANON_KEY);
});

Deno.test("a session Supabase Auth accepts but the OAuth server did not issue is refused before Auth is asked", async () => {
  const run = await send({
    token: ADA_SESSION,
    body: { jsonrpc: "2.0", id: 1, method: "ping" },
  });
  assert.equal(run.status, 401);
  assert.equal(run.fake.calls.length, 0);
});

Deno.test("a local stack's metadata names its own SUPABASE_URL as the resource's origin and Auth's issuer", async () => {
  const run = await send({
    token: null,
    method: "GET",
    path: "/mcp/oauth-protected-resource",
  });
  assert.equal(run.status, 200);
  assert.deepEqual(run.json, {
    resource: "http://kong:8000/functions/v1/mcp",
    authorization_servers: ["http://kong:8000/auth/v1"],
    bearer_methods_supported: ["header"],
    resource_name: "smartman",
  });
});

Deno.test("on the custom domain the 401 and the metadata name its URL as the resource, the authorization server staying Auth's issuer", async () => {
  const headers = { "X-Forwarded-Host": "api.knowno.app" };
  const challenge = await send({
    token: null,
    headers,
    supabaseUrl: PROJECT,
    body: { jsonrpc: "2.0", id: 1, method: "ping" },
  });
  assert.equal(challenge.status, 401);
  assert.equal(
    challenge.headers.get("WWW-Authenticate"),
    'Bearer resource_metadata="https://api.knowno.app/functions/v1/mcp/oauth-protected-resource"',
  );
  const metadata = await send({
    token: null,
    headers,
    supabaseUrl: PROJECT,
    method: "GET",
    path: "/mcp/oauth-protected-resource",
  });
  assert.deepEqual(metadata.json, {
    resource: "https://api.knowno.app/functions/v1/mcp",
    authorization_servers: [`${PROJECT}/auth/v1`],
    bearer_methods_supported: ["header"],
    resource_name: "smartman",
  });
});

Deno.test("a forwarded host outside CUSTOM_DOMAINS is never named and falls back to SUPABASE_URL's host, as the custom domain is named", async () => {
  for (
    const host of [
      "evil.example",
      "api.knowno.app.evil.example",
      "abcdefghijklmnopqrst.supabase.co",
    ]
  ) {
    const metadata = await send({
      token: null,
      headers: { "X-Forwarded-Host": host },
      supabaseUrl: PROJECT,
      method: "GET",
      path: "/mcp/oauth-protected-resource",
    });
    assert.equal(
      (metadata.json as Row).resource,
      `${PROJECT}/functions/v1/mcp`,
      host,
    );
    const challenge = await send({
      token: null,
      headers: { "X-Forwarded-Host": host },
      supabaseUrl: PROJECT,
    });
    assert.equal(
      challenge.headers.get("WWW-Authenticate"),
      `Bearer resource_metadata="${PROJECT}/functions/v1/mcp/oauth-protected-resource"`,
      host,
    );
  }
  // The control: the same request from the custom domain is named on it.
  const listed = await send({
    token: null,
    headers: { "X-Forwarded-Host": "api.knowno.app" },
    supabaseUrl: PROJECT,
    method: "GET",
    path: "/mcp/oauth-protected-resource",
  });
  assert.equal(
    (listed.json as Row).resource,
    "https://api.knowno.app/functions/v1/mcp",
  );
});

Deno.test("a SUPABASE_URL that is not an http(s) URL leaves the function unconfigured, as a valid one configures it", async () => {
  for (
    const supabaseUrl of ["not a url", "ftp://abcdefghijklmnopqrst.supabase.co"]
  ) {
    const run = await send({
      token: null,
      supabaseUrl,
      method: "GET",
      path: "/mcp/oauth-protected-resource",
    });
    assert.equal(run.status, 503, supabaseUrl);
  }
  const configured = await send({
    token: null,
    supabaseUrl: PROJECT,
    method: "GET",
    path: "/mcp/oauth-protected-resource",
  });
  assert.equal(configured.status, 200);
});

Deno.test("initialize answers the offered version when served and the newest otherwise, with the tools capability", async () => {
  const offered = await send({
    body: {
      jsonrpc: "2.0",
      id: 1,
      method: "initialize",
      params: { protocolVersion: "2025-06-18" },
    },
  });
  const result = (offered.json as { result: Row }).result;
  assert.equal(result.protocolVersion, "2025-06-18");
  assert.deepEqual(result.capabilities, { tools: { listChanged: false } });
  assert.equal(offered.headers.get("Mcp-Session-Id"), null);
  const unknown = await send({
    body: {
      jsonrpc: "2.0",
      id: 1,
      method: "initialize",
      params: { protocolVersion: "2024-11-05" },
    },
  });
  assert.equal(
    (unknown.json as { result: Row }).result.protocolVersion,
    "2025-11-25",
  );
});

Deno.test("a notification is accepted with 202 and no body; a GET is 405", async () => {
  const notification = await send({
    body: { jsonrpc: "2.0", method: "notifications/initialized" },
  });
  assert.equal(notification.status, 202);
  assert.equal(notification.json, null);
  const get = await send({ method: "GET" });
  assert.equal(get.status, 405);
  assert.equal(get.headers.get("Allow"), "POST");
});

Deno.test("a request carrying an Origin is refused with 403, and one without is served", async () => {
  const body = { jsonrpc: "2.0", id: 1, method: "ping" };
  assert.equal(
    (await send({ body, headers: { Origin: "https://evil.example" } })).status,
    403,
  );
  assert.equal((await send({ body })).status, 200);
});

Deno.test("a protocol version header this server does not speak is refused with 400, and a served one is answered", async () => {
  const body = { jsonrpc: "2.0", id: 1, method: "tools/list" };
  const modern = await send({
    body,
    headers: { "MCP-Protocol-Version": "2026-07-28" },
  });
  assert.equal(modern.status, 400);
  assert.equal((modern.json as { error: { code: number } }).error.code, -32600);
  const served = await send({
    body,
    headers: { "MCP-Protocol-Version": "2025-11-25" },
  });
  assert.equal(served.status, 200);
  const tools =
    (served.json as { result: { tools: { name: string }[] } }).result.tools;
  assert.deepEqual(tools.map((tool) => tool.name), [
    "list_decks",
    "list_cards",
    "search_cards",
    "create_deck",
    "add_cards",
  ]);
});

Deno.test("list_decks lists the caller's live decks with their live card counts, never another user's public deck", async () => {
  const { result, fake } = await call("list_decks", {});
  assert.deepEqual(result.structuredContent, {
    decks: [
      { id: ADA_DECK, name: "영단어", card_count: 3 },
      { id: ADA_OTHER_DECK, name: "Biology", card_count: 1 },
    ],
  });
  assert.deepEqual(
    JSON.parse(result.content[0]!.text),
    result.structuredContent,
  );
  assert.ok(
    fake.calls.every((c) =>
      !c.headers.get("Authorization")?.includes(ANON_KEY)
    ),
  );
});

Deno.test("list_cards pages a deck's live cards as text, a sense's label in brackets and a cloze's back empty", async () => {
  const first = await call("list_cards", { deck_id: ADA_DECK, limit: 2 });
  assert.deepEqual(first.result.structuredContent, {
    deck: { id: ADA_DECK, name: "영단어" },
    total: 3,
    cards: [
      {
        id: "00000000-0000-7000-8000-000000000c01",
        front: "apple",
        back: "[명] 사과\n  - An apple a day.",
      },
      {
        id: "00000000-0000-7000-8000-000000000c02",
        front: "Banana",
        back: "바나나",
      },
    ],
    next_offset: 2,
  });
  const last = await call("list_cards", {
    deck_id: ADA_DECK,
    limit: 2,
    offset: 2,
  });
  assert.deepEqual(last.result.structuredContent?.cards, [
    {
      id: "00000000-0000-7000-8000-000000000c03",
      front: "The cherry is red",
      back: "",
    },
  ]);
  assert.equal(last.result.structuredContent?.next_offset, null);
});

Deno.test("list_cards refuses another user's public deck, which row-level security lets the caller read, and serves the caller's own", async () => {
  const foreign = await call("list_cards", { deck_id: GRACE_PUBLIC_DECK });
  assert.equal(foreign.result.isError, true);
  assert.match(foreign.result.content[0]!.text, /list_decks/);
  const own = await call("list_cards", { deck_id: ADA_OTHER_DECK });
  assert.equal(own.result.isError, undefined);
});

Deno.test("search_cards matches either side ignoring case across the caller's decks, a cloze on its front alone", async () => {
  const apple = await call("search_cards", { query: "APPLE" });
  assert.deepEqual(
    (apple.result.structuredContent?.cards as Row[]).map((c) => c.id),
    [
      "00000000-0000-7000-8000-000000000c01",
      "00000000-0000-7000-8000-000000000c05",
    ],
  );
  assert.deepEqual((apple.result.structuredContent?.cards as Row[])[1]?.deck, {
    id: ADA_OTHER_DECK,
    name: "Biology",
  });
  const stale = await call("search_cards", { query: "stale back" });
  assert.deepEqual(stale.result.structuredContent, {
    cards: [],
    truncated: false,
  });
  const front = await call("search_cards", { query: "cherry" });
  assert.equal((front.result.structuredContent?.cards as Row[]).length, 1);
  const limited = await call("search_cards", { query: "a", limit: 1 });
  assert.equal(limited.result.structuredContent?.truncated, true);
});

Deno.test("create_deck stores a private deck of the caller's under a version 7 id and returns it", async () => {
  const { result, fake } = await call("create_deck", { name: "  Spanish  " });
  const deck = result.structuredContent?.deck as { id: string; name: string };
  assert.equal(deck.name, "Spanish");
  assert.match(
    deck.id,
    /^[0-9a-f]{8}-[0-9a-f]{4}-7[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/,
  );
  const stored = fake.decks.find((row) => row.id === deck.id);
  assert.equal(stored?.user_id, ADA);
  assert.equal(stored?.visibility, "private");
  assert.equal(stored?.created_at, stored?.updated_at);
  const blank = await call("create_deck", { name: "   " });
  assert.equal(blank.result.isError, true);
});

Deno.test("add_cards stores the rows the web's direct entry writes: text and senses blocks, the card key and a free template", async () => {
  const { result, fake } = await call("add_cards", {
    deck_id: ADA_DECK,
    cards: [
      {
        front: "  Run  ",
        back: "달리다",
        labels: ["동", "informal"],
        examples: ["I run."],
      },
      { front: "cat", back: "고양이" },
    ],
  });
  const added = result.structuredContent?.added as {
    index: number;
    id: string;
  }[];
  assert.deepEqual(added.map((a) => a.index), [0, 1]);
  const run = fake.cards.find((row) => row.id === added[0]!.id)!;
  const { id: _f, ...front } = (run.front as Row[])[0]!;
  const { id: _b, ...back } = (run.back as Row[])[0]!;
  assert.deepEqual(front, { type: "text", v: 1, payload: { text: "Run" } });
  assert.deepEqual(back, {
    type: "senses",
    v: 1,
    payload: {
      senses: [{
        labels: [
          { kind: "part_of_speech", category: "verb", text: "동" },
          { kind: "other", category: null, text: "informal" },
        ],
        meaning: "달리다",
        examples: ["I run."],
      }],
    },
  });
  assert.equal(run.card_key, "run");
  assert.equal(run.template, "free");
  assert.equal(run.template_version, 1);
  assert.equal(run.source, "import");
  assert.equal(run.user_id, ADA);
  assert.equal(run.deck_id, ADA_DECK);
  assert.equal(run.created_at, run.updated_at);
  assert.equal(run.revision, undefined);
  const cat = fake.cards.find((row) => row.id === added[1]!.id)!;
  const { id: _c, ...catBack } = (cat.back as Row[])[0]!;
  assert.deepEqual(catBack, {
    type: "text",
    v: 1,
    payload: { text: "고양이" },
  });
});

Deno.test("add_cards skips a front already in the deck or earlier in the call, ignoring case and width, and never overwrites", async () => {
  const { result, fake } = await call("add_cards", {
    deck_id: ADA_DECK,
    cards: [
      { front: "ＡＰＰＬＥ", back: "different" },
      { front: "grape", back: "포도" },
      { front: "Grape ", back: "포도 again" },
    ],
  });
  assert.deepEqual(
    (result.structuredContent?.added as Row[]).map((a) => a.index),
    [1],
  );
  const skipped = result.structuredContent?.skipped as Row[];
  assert.deepEqual(skipped.map((s) => [s.index, s.existing_card_id]), [
    [0, "00000000-0000-7000-8000-000000000c01"],
    [2, (result.structuredContent?.added as Row[])[0]!.id],
  ]);
  const apple = fake.cards.find((row) =>
    row.id === "00000000-0000-7000-8000-000000000c01"
  )!;
  assert.equal(
    ((apple.back as Row[])[0]!.payload as Row).senses !== undefined,
    true,
  );
  assert.equal(fake.cards.filter((row) => row.deck_id === ADA_DECK).length, 5);
});

Deno.test("add_cards adds a duplicate front when allow_duplicates is true", async () => {
  const { result } = await call("add_cards", {
    deck_id: ADA_DECK,
    cards: [{ front: "apple", back: "또 사과" }],
    allow_duplicates: true,
  });
  assert.equal((result.structuredContent?.added as Row[]).length, 1);
  assert.deepEqual(result.structuredContent?.skipped, []);
});

Deno.test("add_cards refuses a card with an empty back by its index and adds the rest", async () => {
  const { result } = await call("add_cards", {
    deck_id: ADA_DECK,
    cards: [{ front: "empty", back: "  " }, { front: "kept", back: "남김" }],
  });
  assert.deepEqual(result.structuredContent?.refused, [
    { index: 0, reason: "back must be text of 1 to 2000 characters." },
  ]);
  assert.deepEqual(
    (result.structuredContent?.added as Row[]).map((a) => a.index),
    [1],
  );
});

Deno.test("add_cards refuses 101 cards and writes nothing, and adds 100", async () => {
  const many = (count: number) =>
    Array.from(
      { length: count },
      (_, index) => ({ front: `word ${index}`, back: "뜻" }),
    );
  const over = await call("add_cards", { deck_id: ADA_DECK, cards: many(101) });
  assert.equal(over.result.isError, true);
  assert.match(over.result.content[0]!.text, /at most 100 cards per call/);
  assert.ok(over.fake.calls.every((c) => c.method !== "POST"));
  const cap = await call("add_cards", { deck_id: ADA_DECK, cards: many(100) });
  assert.equal((cap.result.structuredContent?.added as Row[]).length, 100);
  assert.equal(cap.fake.calls.filter((c) => c.method === "POST").length, 1);
});

Deno.test("add_cards refuses another user's deck and writes nothing, as the same call adds to the caller's own", async () => {
  const cards = [{ front: "pear", back: "배" }];
  const foreign = await call("add_cards", {
    deck_id: GRACE_PUBLIC_DECK,
    cards,
  });
  assert.equal(foreign.result.isError, true);
  assert.ok(foreign.fake.calls.every((c) => c.method !== "POST"));
  assert.equal(
    foreign.fake.cards.filter((row) => row.deck_id === GRACE_PUBLIC_DECK)
      .length,
    1,
  );
  const own = await call(
    "add_cards",
    { deck_id: GRACE_PUBLIC_DECK, cards },
    seed(),
    GRACE_TOKEN,
  );
  assert.equal((own.result.structuredContent?.added as Row[]).length, 1);
});

Deno.test("a tool whose database cannot be reached answers an error result the model can retry on", async () => {
  const fake = seed();
  fake.rest = "offline";
  const { result, logs } = await call("list_decks", {}, fake);
  assert.equal(result.isError, true);
  assert.match(result.content[0]!.text, /try again/);
  assert.deepEqual(logs, [{
    user_id: ADA,
    method: "tools/call",
    tool: "list_decks",
    outcome: "unavailable",
  }]);
});

Deno.test("an unknown tool is refused with the names of the tools", async () => {
  const { result } = await call("delete_deck", {});
  assert.equal(result.isError, true);
  assert.match(
    result.content[0]!.text,
    /list_decks, list_cards, search_cards, create_deck, add_cards/,
  );
});

Deno.test("cards added in one call within one millisecond are listed in the call's order", async () => {
  const fake = seed();
  // A frozen clock, and random bits that fall with each id, so the ids sort against insertion.
  let fall = 255;
  const ids: IdSource = {
    now: () => Date.UTC(2026, 9, 29),
    random: (bytes) => new Uint8Array(bytes).fill(fall--),
  };
  const cards = ["first", "second", "third"].map((front) => ({
    front,
    back: "뜻",
  }));
  await call(
    "add_cards",
    { deck_id: ADA_OTHER_DECK, cards },
    fake,
    ADA_TOKEN,
    ids,
  );
  const { result } = await call(
    "list_cards",
    { deck_id: ADA_OTHER_DECK },
    fake,
  );
  assert.deepEqual(
    (result.structuredContent?.cards as Row[]).map((card) => card.front),
    ["cell", "first", "second", "third"],
  );
});
