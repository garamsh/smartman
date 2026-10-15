import { randomUUID } from "node:crypto";

import { expect, test } from "@playwright/test";
import { createServerClient } from "@supabase/ssr";
import { createClient } from "@supabase/supabase-js";

// The local stack supabase/test-web.sh starts, whose URL and publishable key the app was built
// with. Password sign-up and sign-in are enabled on the local stack alone (supabase/config.toml).
const supabaseUrl = process.env.E2E_SUPABASE_URL;
const supabaseKey = process.env.E2E_SUPABASE_KEY;

test.skip(
  !supabaseUrl || !supabaseKey,
  "needs the local Supabase stack supabase/test-web.sh starts, which sets E2E_SUPABASE_URL and E2E_SUPABASE_KEY",
);

// What the browser reported, printed when the test fails: the write runs out of sight.
const browserLog: string[] = [];
test.afterEach(({}, testInfo) => {
  if (testInfo.status !== testInfo.expectedStatus) console.log(browserLog.join("\n"));
  browserLog.length = 0;
});

test("a signed-in user studies a card, and the server holds its review and state", async ({
  page,
  context,
  baseURL,
}) => {
  if (!supabaseUrl || !supabaseKey || !baseURL) throw new Error("skipped above");
  page.on("console", (message) => browserLog.push(`console ${message.type()}: ${message.text()}`));
  page.on("requestfailed", (request) =>
    browserLog.push(
      `failed ${request.method()} ${request.url()}: ${request.failure()?.errorText ?? ""}`,
    ),
  );
  page.on("response", (response) => {
    if (response.request().method() === "POST") {
      browserLog.push(`POST ${response.url()} answered ${String(response.status())}`);
    }
  });
  const email = `web-study-${randomUUID()}@example.com`;
  const password = "web-study-password";

  // The session cookies a browser holds after signing in, written by @supabase/ssr itself.
  const cookies = new Map<string, string>();
  const browserSession = createServerClient(supabaseUrl, supabaseKey, {
    cookies: {
      getAll: () => [...cookies].map(([name, value]) => ({ name, value })),
      setAll: (written) => {
        for (const { name, value } of written) cookies.set(name, value);
      },
    },
  });
  const signUp = await browserSession.auth.signUp({ email, password });
  expect(signUp.error).toBeNull();
  const userId = signUp.data.user?.id;
  expect(cookies.size).toBeGreaterThan(0);
  await context.addCookies([...cookies].map(([name, value]) => ({ name, value, url: baseURL })));

  // The phone's sync has pushed a deck with one new card.
  const phone = createClient(supabaseUrl, supabaseKey, { auth: { persistSession: false } });
  expect((await phone.auth.signInWithPassword({ email, password })).error).toBeNull();
  const deckId = randomUUID();
  const cardId = randomUUID();
  const now = new Date().toISOString();
  const side = (text: string) => [{ type: "text", payload: { text } }];
  expect(
    (
      await phone.from("decks").insert({
        id: deckId,
        user_id: userId,
        name: "French",
        created_at: now,
        updated_at: now,
      })
    ).error,
  ).toBeNull();
  expect(
    (
      await phone.from("cards").insert({
        id: cardId,
        user_id: userId,
        deck_id: deckId,
        front: side("chat"),
        back: side("cat"),
        card_key: "chat",
        source: "manual",
        created_at: now,
        updated_at: now,
      })
    ).error,
  ).toBeNull();

  await page.goto("/");
  await page.getByRole("link", { name: "French, 카드 1장, 오늘 1", exact: true }).click();
  await page.getByRole("link", { name: "학습 · 1장", exact: true }).click();
  await expect(page.getByRole("group", { name: "문제", exact: true })).toHaveText("chat");
  await page.keyboard.press("Space");
  await expect(page.getByRole("group", { name: "답", exact: true })).toHaveText("cat");
  await page.keyboard.press("k");
  await expect(page.getByRole("heading", { name: "학습 끝", exact: true })).toBeVisible();

  // The write runs after the screen changed; the state is written after the review.
  await expect
    .poll(async () => (await phone.from("card_states").select("card_id")).data?.length)
    .toBe(1);
  const reviews = await phone.from("reviews").select("card_id, rating, fuzz_factor, revision");
  expect(reviews.error).toBeNull();
  expect(reviews.data).toEqual([
    expect.objectContaining({ card_id: cardId, rating: "good", fuzz_factor: expect.any(Number) }),
  ]);
  const states = await phone.from("card_states").select("card_id, stability, due, revision");
  expect(states.data).toEqual([
    expect.objectContaining({ card_id: cardId, stability: expect.any(Number) }),
  ]);
  // A new card answered 안다 is next due days from now, as the engine schedules it.
  expect(Date.parse(String(states.data?.[0]?.due))).toBeGreaterThan(Date.now() + 86_400_000);
});
