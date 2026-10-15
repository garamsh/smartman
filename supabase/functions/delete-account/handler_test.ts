// The handler end to end, with Supabase Auth replaced by a recording fake fetch.
// The suite runs without write or network permission, so a write anywhere fails the run.
import assert from "node:assert/strict";
import { readConfig } from "./config.ts";
import { createHandler, type LogEntry } from "./handler.ts";

const SUPABASE_URL = "https://project.supabase.test";
const SERVICE_ROLE_KEY = "service-role-key";
const ADA = "00000000-0000-4000-8000-00000000000a";
const GRACE = "00000000-0000-4000-8000-00000000000b";

/** The users the fake Auth server knows, by the bearer token that signs each in. */
const TOKENS: Record<string, { id: string; is_anonymous?: boolean }> = {
  "Bearer ada-token": { id: ADA },
  "Bearer grace-token": { id: GRACE },
  "Bearer anonymous-sign-in": { id: ADA, is_anonymous: true },
};

const ENV: Record<string, string> = {
  SUPABASE_URL,
  SUPABASE_SERVICE_ROLE_KEY: SERVICE_ROLE_KEY,
};

type Fake = {
  /** The admin API's answer to a delete, or "offline" for a request that never arrives. */
  admin: number | "offline";
  /** Auth's answer to the user lookup when it is not the user's. */
  lookup: number | null;
  calls: { url: string; method: string; headers: Headers }[];
};

function fakeFetch(fake: Fake): typeof fetch {
  return (input, init) => {
    const url = String(input);
    const method = init?.method ?? "GET";
    const headers = new Headers(init?.headers);
    fake.calls.push({ url, method, headers });
    if (url === `${SUPABASE_URL}/auth/v1/user`) {
      if (fake.lookup !== null) {
        return Promise.resolve(new Response(null, { status: fake.lookup }));
      }
      const user = TOKENS[headers.get("Authorization") ?? ""];
      return Promise.resolve(
        user === undefined
          ? Response.json({ code: 403 }, { status: 403 })
          : Response.json({ ...user, role: "authenticated" }),
      );
    }
    if (url.startsWith(`${SUPABASE_URL}/auth/v1/admin/users/`)) {
      if (fake.admin === "offline") {
        return Promise.reject(new TypeError("error sending request"));
      }
      return Promise.resolve(Response.json({}, { status: fake.admin }));
    }
    throw new Error(`unexpected request to ${url}`);
  };
}

type Run = {
  status: number;
  text: string;
  logs: LogEntry[];
  console: string[];
  deleted: string[];
  fake: Fake;
};

async function run(
  options: {
    authorization?: string | null;
    method?: string;
    body?: string;
    admin?: number | "offline";
    lookup?: number;
    env?: Record<string, string | undefined>;
  } = {},
): Promise<Run> {
  const fake: Fake = {
    admin: options.admin ?? 200,
    lookup: options.lookup ?? null,
    calls: [],
  };
  const env = { ...ENV, ...options.env };
  const logs: LogEntry[] = [];
  const handler = createHandler({
    config: readConfig((name) => env[name]),
    fetch: fakeFetch(fake),
    log: (entry) => logs.push(entry),
  });
  const headers = new Headers();
  const authorization = options.authorization === undefined
    ? "Bearer ada-token"
    : options.authorization;
  if (authorization !== null) headers.set("Authorization", authorization);
  const method = options.method ?? "POST";
  const request = new Request("https://functions.test/delete-account", {
    method,
    headers,
    body: method === "POST" ? options.body : undefined,
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
  return {
    status: response.status,
    text: await response.text(),
    logs,
    console: printed,
    deleted: fake.calls
      .filter((call) => call.method === "DELETE")
      .map((call) => call.url.slice(call.url.lastIndexOf("/") + 1)),
    fake,
  };
}

Deno.test("the suite runs without write or network permission", () => {
  assert.notEqual(
    Deno.permissions.querySync({ name: "write" }).state,
    "granted",
  );
  assert.notEqual(Deno.permissions.querySync({ name: "net" }).state, "granted");
});

Deno.test("a signed-in user is deleted through the admin API with the service-role key, and answered 204", async () => {
  const r = await run();
  assert.equal(r.status, 204);
  assert.equal(r.text, "");
  assert.deepEqual(r.deleted, [ADA]);
  const call = r.fake.calls.find((c) => c.method === "DELETE")!;
  assert.equal(call.url, `${SUPABASE_URL}/auth/v1/admin/users/${ADA}`);
  assert.equal(call.headers.get("apikey"), SERVICE_ROLE_KEY);
  assert.equal(call.headers.get("Authorization"), `Bearer ${SERVICE_ROLE_KEY}`);
});

Deno.test("a request without a signed-in user is refused with 401 and deletes no one", async () => {
  for (
    const authorization of [
      null,
      "Bearer anon-key",
      "Bearer anonymous-sign-in",
      "Basic ada-token",
    ]
  ) {
    const r = await run({ authorization });
    assert.equal(r.status, 401, `authorization ${authorization}`);
    assert.deepEqual(JSON.parse(r.text), { error: "unauthenticated" });
    assert.deepEqual(r.deleted, []);
  }
  const control = await run();
  assert.equal(control.status, 204, "control: the signed-in token is accepted");
  assert.deepEqual(control.deleted, [ADA]);
});

Deno.test("the user deleted is the token's, whatever id the body names", async () => {
  for (
    const body of [
      JSON.stringify({ user_id: GRACE }),
      JSON.stringify({ id: GRACE, userId: GRACE }),
      GRACE,
      "not json",
    ]
  ) {
    const r = await run({ body });
    assert.equal(r.status, 204, body);
    assert.deepEqual(r.deleted, [ADA], `body ${body} deletes the caller only`);
  }
  // The control: the id comes from the token, so Grace's token deletes Grace.
  const control = await run({
    authorization: "Bearer grace-token",
    body: JSON.stringify({ user_id: ADA }),
  });
  assert.deepEqual(control.deleted, [GRACE]);
});

Deno.test("a deletion the admin API refuses or never receives answers 502", async () => {
  for (const admin of [500, 404, "offline"] as const) {
    const r = await run({ admin });
    assert.equal(r.status, 502, `admin ${admin}`);
    assert.deepEqual(JSON.parse(r.text), { error: "delete_failed" });
    assert.deepEqual(r.logs, [{ user_id: ADA, outcome: "delete_failed" }]);
  }
});

Deno.test("a user lookup that fails answers 502 without deleting", async () => {
  const r = await run({ lookup: 500 });
  assert.equal(r.status, 502);
  assert.deepEqual(JSON.parse(r.text), { error: "delete_failed" });
  assert.deepEqual(r.deleted, []);
});

Deno.test("a method other than POST is refused with 405", async () => {
  const r = await run({ method: "GET" });
  assert.equal(r.status, 405);
  assert.equal(r.fake.calls.length, 0);
});

Deno.test("a missing platform variable answers 503 before any call", async () => {
  for (const name of ["SUPABASE_URL", "SUPABASE_SERVICE_ROLE_KEY"]) {
    const r = await run({ env: { [name]: undefined } });
    assert.equal(r.status, 503, name);
    assert.deepEqual(JSON.parse(r.text), { error: "not_configured" });
    assert.equal(r.fake.calls.length, 0);
  }
});

Deno.test("each request logs exactly its user and outcome, and prints nothing else", async () => {
  const deleted = await run();
  assert.deepEqual(deleted.logs, [{ user_id: ADA, outcome: "deleted" }]);
  const refused = await run({ authorization: "Bearer anon-key" });
  assert.deepEqual(refused.logs, [{
    user_id: null,
    outcome: "unauthenticated",
  }]);
  for (const r of [deleted, refused]) {
    assert.deepEqual(r.console, []);
  }
});

Deno.test("an unexpected failure logs internal and propagates", async () => {
  const logs: LogEntry[] = [];
  const handler = createHandler({
    config: readConfig((name) => ENV[name]),
    fetch: () => {
      throw new RangeError("a bug");
    },
    log: (entry) => logs.push(entry),
  });
  await assert.rejects(
    handler(
      new Request("https://functions.test/delete-account", {
        method: "POST",
        headers: { Authorization: "Bearer ada-token" },
      }),
    ),
    RangeError,
  );
  assert.deepEqual(logs, [{ user_id: null, outcome: "internal" }]);
});
