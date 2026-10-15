import { randomUUID } from "node:crypto";

import { expect, type Page, test } from "@playwright/test";
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

// Where to save screenshots of each screen in both themes, for review; none are taken unless it
// names a directory.
const screenshots = process.env.E2E_SCREENSHOTS;

async function shot(page: Page, name: string) {
  if (!screenshots) return;
  for (const colorScheme of ["light", "dark"] as const) {
    await page.emulateMedia({ colorScheme });
    await page.screenshot({
      path: `${screenshots}/${colorScheme}/web-${name}.png`,
      fullPage: true,
    });
  }
  await page.emulateMedia({ colorScheme: null });
}

// What the browser reported, printed when the test fails: the write runs out of sight.
const browserLog: string[] = [];
test.afterEach(({}, testInfo) => {
  if (testInfo.status !== testInfo.expectedStatus) console.log(browserLog.join("\n"));
  browserLog.length = 0;
});

test("a signed-in user studies two cards, and the server holds their reviews and states", async ({
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
  const now = new Date().toISOString();
  const side = (text: string) => [{ type: "text", payload: { text } }];
  // Two new cards, so the second is shown under the first one's answer; the deck is published.
  const backs = new Map([
    ["chat", "cat"],
    ["chien", "dog"],
  ]);
  const cardIds = new Map([...backs.keys()].map((front) => [front, randomUUID()]));
  expect(
    (
      await phone.from("decks").insert({
        id: deckId,
        user_id: userId,
        name: "French",
        visibility: "public",
        published_at: now,
        created_at: now,
        updated_at: now,
      })
    ).error,
  ).toBeNull();
  expect(
    (
      await phone.from("cards").insert(
        [...backs].map(([front, back]) => ({
          id: cardIds.get(front),
          user_id: userId,
          deck_id: deckId,
          front: side(front),
          back: side(back),
          card_key: front,
          source: "manual",
          created_at: now,
          updated_at: now,
        })),
      )
    ).error,
  ).toBeNull();

  await page.goto("/");
  const deckRow = page.getByRole("link", { name: "French, 카드 2장, 공개, 오늘 2", exact: true });
  await expect(deckRow).toBeVisible();
  // The deck list carries no account content; the account page, the control below, does.
  await expect(page.getByText(email)).toHaveCount(0);
  await expect(page.getByRole("button", { name: "로그아웃" })).toHaveCount(0);
  await shot(page, "01-home");
  await deckRow.click();
  await expect(page.getByRole("heading", { name: "French", exact: true })).toBeVisible();
  await shot(page, "02-deck");
  await page.getByRole("link", { name: "학습하기 · 2장", exact: true }).click();

  const question = page.getByRole("group", { name: "문제", exact: true });
  const answer = page.getByRole("group", { name: "답", exact: true });
  await expect(question).toHaveText(/^(chat|chien)$/);
  const first = (await question.textContent()) ?? "";
  await shot(page, "03-study-question");
  await page.keyboard.press("Space");
  await expect(answer).toHaveText(backs.get(first) ?? "");
  await shot(page, "04-study-revealed");
  await page.keyboard.press("k");
  const second = first === "chat" ? "chien" : "chat";
  await expect(question).toHaveText(second);
  await expect(page.getByRole("region", { name: "이전 답" }).getByRole("button")).toHaveCount(1);
  await page.keyboard.press("Space");
  await expect(answer).toHaveText(backs.get(second) ?? "");
  await shot(page, "05-study-stack");
  await page.keyboard.press("k");
  await expect(
    page.getByRole("heading", { name: "오늘 할 카드를 마쳤어요", exact: true }),
  ).toBeVisible();
  // Shown once both writes are saved: a new card answered 안다 is next due days from now.
  await expect(
    page.getByText(/^다음 복습은 \d+일 뒤예요\. 잊을 때쯤 다시 보여 드릴게요\.$/),
  ).toBeVisible();
  await shot(page, "06-summary");

  // The writes ran after the screen changed; each state is written after its review.
  await expect
    .poll(async () => (await phone.from("card_states").select("card_id")).data?.length)
    .toBe(2);
  const reviews = await phone.from("reviews").select("card_id, rating, fuzz_factor, revision");
  expect(reviews.error).toBeNull();
  expect(reviews.data).toEqual(
    expect.arrayContaining(
      [...cardIds.values()].map((cardId) =>
        expect.objectContaining({
          card_id: cardId,
          rating: "good",
          fuzz_factor: expect.any(Number),
        }),
      ),
    ),
  );
  expect(reviews.data).toHaveLength(2);
  const states = await phone.from("card_states").select("card_id, stability, due, revision");
  expect(states.data).toHaveLength(2);
  for (const state of states.data ?? []) {
    expect(state).toEqual(expect.objectContaining({ stability: expect.any(Number) }));
    // A new card answered 안다 is next due days from now, as the engine schedules it.
    expect(Date.parse(String(state.due))).toBeGreaterThan(Date.now() + 86_400_000);
  }

  await page.goto("/account");
  await expect(page.getByRole("heading", { name: "계정", exact: true })).toBeVisible();
  await expect(page.getByText(email)).toBeVisible();
  await expect(page.getByRole("button", { name: "로그아웃" })).toBeVisible();
  await shot(page, "07-account");
});
