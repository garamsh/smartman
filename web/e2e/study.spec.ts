import { randomUUID } from "node:crypto";

import { type BrowserContext, expect, type Page, test } from "@playwright/test";
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

/**
 * Signs up a new user with a password and gives [context] the session cookies a browser holds
 * after signing in, written by @supabase/ssr itself.
 */
async function signUpInBrowser(
  context: BrowserContext,
  baseURL: string,
  email: string,
  password: string,
) {
  if (!supabaseUrl || !supabaseKey) throw new Error("skipped above");
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
  expect(cookies.size).toBeGreaterThan(0);
  await context.addCookies([...cookies].map(([name, value]) => ({ name, value, url: baseURL })));
  return signUp.data.user?.id;
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

  await page.goto("/login");
  await shot(page, "00-login");
  const userId = await signUpInBrowser(context, baseURL, email, password);

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
  // No card is left today: the completion card takes the current card's place, below the stack.
  const completion = page.getByRole("region", { name: "오늘 학습 완료", exact: true });
  await expect(completion).toBeVisible();
  await expect(question).toHaveCount(0);
  await expect(page.getByRole("region", { name: "이전 답" }).getByRole("button")).toHaveCount(2);
  await expect(completion.getByText("2 안다", { exact: true })).toBeVisible();
  await expect(completion.getByText("연속 1일", { exact: true })).toBeVisible();
  await shot(page, "06-study-complete");

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

  // 계속 학습 goes on as practice on the same page, over the two cards, and writes nothing.
  const studyUrl = page.url();
  const posts = browserLog.filter((line) => line.startsWith("POST ")).length;
  await completion.getByRole("button", { name: "계속 학습", exact: true }).click();
  await expect(question).toHaveText(/^(chat|chien)$/);
  expect(page.url()).toBe(studyUrl);
  await page.keyboard.press("j");
  await expect(question).toHaveText(/^(chat|chien)$/);
  await shot(page, "06b-study-practice");
  await page.keyboard.press("k");
  await page.keyboard.press("z");
  await expect(page.getByRole("region", { name: "이전 답" }).getByRole("button")).toHaveCount(4);
  expect(page.url()).toBe(studyUrl);
  expect(browserLog.filter((line) => line.startsWith("POST ")).length).toBe(posts);
  const practisedReviews = await phone
    .from("reviews")
    .select("card_id, rating, fuzz_factor, revision");
  expect(practisedReviews.data).toEqual(reviews.data);
  const practisedStates = await phone
    .from("card_states")
    .select("card_id, stability, due, revision");
  expect(practisedStates.data).toEqual(states.data);

  // Esc leaves for the deck list.
  await page.keyboard.press("Escape");
  await expect(page).toHaveURL(`${baseURL}/`);

  // A deck whose one card is due next week, and was not answered today, has nothing to study.
  const laterDeck = randomUUID();
  const laterCard = randomUUID();
  const nextWeek = new Date(Date.now() + 7 * 86_400_000).toISOString();
  expect(
    (
      await phone.from("decks").insert({
        id: laterDeck,
        user_id: userId,
        name: "Later",
        created_at: now,
        updated_at: now,
      })
    ).error,
  ).toBeNull();
  expect(
    (
      await phone.from("cards").insert({
        id: laterCard,
        user_id: userId,
        deck_id: laterDeck,
        front: side("plus tard"),
        back: side("later"),
        card_key: "plus tard",
        source: "manual",
        created_at: now,
        updated_at: now,
      })
    ).error,
  ).toBeNull();
  expect(
    (
      await phone.from("card_states").insert({
        user_id: userId,
        card_id: laterCard,
        stability: 7,
        difficulty: 5,
        last_review: now,
        due: nextWeek,
        updated_at: now,
      })
    ).error,
  ).toBeNull();
  await page.goto(`/study?decks=${laterDeck}`);
  await expect(page.getByText("오늘은 학습할 카드가 없어요", { exact: true })).toBeVisible();
  await expect(completion).toHaveCount(0);
  await shot(page, "06c-study-nothing-today");

  await page.goto("/account");
  await expect(page.getByRole("heading", { level: 1, name: "계정", exact: true })).toBeVisible();
  await expect(page.getByText(email)).toBeVisible();
  await expect(page.getByRole("button", { name: "로그아웃" })).toBeVisible();
  await shot(page, "07-account");
});

test("a user with no deck is invited to make one, and the theme they choose survives a reload", async ({
  page,
  context,
  baseURL,
}) => {
  if (!baseURL) throw new Error("skipped above");
  await signUpInBrowser(context, baseURL, `web-empty-${randomUUID()}@example.com`, "web-empty-pw");

  await page.goto("/");
  await expect(
    page.getByRole("heading", { name: "첫 덱을 만들어 볼까요?", exact: true }),
  ).toBeVisible();
  await expect(page.getByRole("link", { name: "모두 학습" })).toHaveCount(0);
  await shot(page, "08-empty-home");

  await page.goto("/account");
  const group = page.getByRole("radiogroup", { name: "화면", exact: true });
  const body = page.locator("body");
  await expect(group.getByRole("radio", { name: "시스템", exact: true })).toBeChecked();
  // The system's dark mode, so 라이트 differs from it and 다크 from the default's light.
  await page.emulateMedia({ colorScheme: "dark" });
  const ground = { light: "rgb(244, 246, 250)", dark: "rgb(14, 20, 36)" };
  for (const [choice, label, colour] of [
    ["light", "라이트", ground.light],
    ["dark", "다크", ground.dark],
    ["system", "시스템", ground.dark],
  ] as const) {
    await group.getByText(label, { exact: true }).click();
    await expect(body).toHaveCSS("background-color", colour);

    await page.reload();

    await expect(group.getByRole("radio", { name: label, exact: true })).toBeChecked();
    await expect(body).toHaveCSS("background-color", colour);
    if (screenshots) {
      await page.screenshot({
        path: `${screenshots}/choice/web-09-account-${choice}.png`,
        fullPage: true,
      });
    }
  }
  await page.emulateMedia({ colorScheme: null });
});

test("each page that waits on the server shows its skeleton, still under reduced motion, where its content then lands", async ({
  browser,
  context,
  baseURL,
}) => {
  if (!supabaseUrl || !supabaseKey || !baseURL) throw new Error("skipped above");
  const email = `web-skeleton-${randomUUID()}@example.com`;
  const password = "web-skeleton-pw";
  const userId = await signUpInBrowser(context, baseURL, email, password);
  const phone = createClient(supabaseUrl, supabaseKey, { auth: { persistSession: false } });
  expect((await phone.auth.signInWithPassword({ email, password })).error).toBeNull();
  const deckId = randomUUID();
  const now = new Date().toISOString();
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
        id: randomUUID(),
        user_id: userId,
        deck_id: deckId,
        front: [{ type: "text", payload: { text: "chat" } }],
        back: [{ type: "text", payload: { text: "cat" } }],
        card_key: "chat",
        source: "manual",
        created_at: now,
        updated_at: now,
      })
    ).error,
  ).toBeNull();

  // Without scripts React never swaps the streamed content in, so the fallback stays on screen.
  const still = await browser.newContext({ javaScriptEnabled: false });
  await still.addCookies(await context.cookies());
  const skeletonPage = await still.newPage();
  const livePage = await context.newPage();
  const pages = [
    { path: "/", name: "home", status: "덱을 불러오는 중이에요.", content: "section", held: 0 },
    {
      path: `/decks/${deckId}`,
      name: "deck",
      status: "덱을 불러오는 중이에요.",
      content: "h1",
      held: 1,
    },
    {
      path: `/study?decks=${deckId}`,
      name: "study",
      status: "카드를 불러오는 중이에요.",
      content: '[aria-label="현재 카드"]',
      held: 1,
    },
    {
      path: "/account",
      name: "account",
      status: "계정을 불러오는 중이에요.",
      content: '[aria-label="프로필"]',
      held: 0,
    },
  ];
  // Each page names its first block of content and the placeholder that holds its place.
  for (const { path, name, status, content, held: placeholder } of pages) {
    await skeletonPage.emulateMedia({ reducedMotion: "no-preference" });
    await skeletonPage.goto(path);
    const busy = skeletonPage.locator('[aria-busy="true"]');
    await expect(busy).toBeVisible();
    await expect(skeletonPage.getByRole("status")).toHaveText(status);
    const placeholders = busy.locator('> [aria-hidden="true"]');
    await expect(placeholders).toHaveCSS("animation-name", "skeleton");
    if (screenshots) {
      for (const colorScheme of ["light", "dark"] as const) {
        await skeletonPage.emulateMedia({ colorScheme });
        await skeletonPage.screenshot({
          path: `${screenshots}/${colorScheme}/web-10-skeleton-${name}.png`,
          fullPage: true,
        });
      }
      await skeletonPage.emulateMedia({ colorScheme: null });
    }

    await skeletonPage.emulateMedia({ reducedMotion: "reduce" });
    await expect(placeholders).toHaveCSS("animation-name", "none");

    // The first block of content takes the place its placeholder held.
    const held = await placeholders.locator("> *").nth(placeholder).boundingBox();
    await livePage.goto(path);
    const block = livePage.locator(content).first();
    await expect(block).toBeVisible();
    const landed = await block.boundingBox();
    expect({ name, top: landed?.y }).toEqual({ name, top: held?.y });
  }
  await still.close();
});

test("the account avatar stays a 56 px circle beside an email too long for one line", async ({
  page,
  context,
  baseURL,
}) => {
  if (!baseURL) throw new Error("skipped above");
  const email = `web-avatar-${randomUUID()}@a-long-subdomain-that-takes-the-email-past-the-card.example.com`;
  await signUpInBrowser(context, baseURL, email, "web-avatar-pw");

  await page.goto("/account");
  const card = page.getByRole("region", { name: "프로필", exact: true });
  const shown = card.getByText(email, { exact: true });
  await expect(shown).toBeVisible();
  await shot(page, "11-account-long-email");
  const avatar = card.locator('[aria-hidden="true"]');
  const cardBox = await card.boundingBox();
  const emailBox = await shown.boundingBox();
  const lineHeight = await shown.evaluate((node) => parseFloat(getComputedStyle(node).lineHeight));
  // The email wraps, so it is long enough to squeeze the avatar if the avatar could shrink.
  expect(emailBox?.height).toBeGreaterThan(lineHeight);
  expect(await avatar.boundingBox()).toMatchObject({ width: 56, height: 56 });
  const radius = await avatar.evaluate((node) => parseFloat(getComputedStyle(node).borderRadius));
  expect(radius).toBeGreaterThanOrEqual(28);
  // The email stays inside the card.
  if (!cardBox || !emailBox) throw new Error("the card and the email are visible above");
  expect(emailBox.x + emailBox.width).toBeLessThanOrEqual(cardBox.x + cardBox.width);
});
