import { randomUUID } from "node:crypto";
import { createServerClient } from "@supabase/ssr";
import { createClient } from "@supabase/supabase-js";
import { expect, test, type Page } from "@playwright/test";
import { untilReacted } from "./until-reacted";

const url = process.env.E2E_SUPABASE_URL;
const key = process.env.E2E_SUPABASE_KEY;
test.skip(!url || !key, "needs a throwaway local Supabase stack; never calls extraction");

async function capture(page: Page, name: string) {
  const directory = process.env.E2E_SCREENSHOTS;
  for (const width of [320, 390, 1280]) {
    await page.setViewportSize({ width, height: width < 1024 ? 844 : 900 });
    for (const colorScheme of ["light", "dark"] as const) {
      await page.emulateMedia({ colorScheme });
      expect(
        await page.evaluate(() => document.documentElement.scrollWidth <= window.innerWidth),
      ).toBe(true);
      if (directory)
        await page.screenshot({
          path: `${directory}/${colorScheme}/web-${name}-${String(width)}.png`,
          fullPage: true,
        });
    }
  }
  await page.setViewportSize({ width: 390, height: 844 });
  await page.emulateMedia({ colorScheme: "light" });
}

test("creates a deck and a card on mobile, warns on a duplicate and keeps saved content", async ({
  page,
  context,
  baseURL,
}) => {
  if (!url || !key || !baseURL) throw new Error("skipped without local stack");
  const jar = new Map<string, string>();
  const auth = createServerClient(url, key, {
    cookies: {
      getAll: () => [...jar].map(([name, value]) => ({ name, value })),
      setAll: (cookies) => {
        for (const { name, value } of cookies) jar.set(name, value);
      },
    },
  });
  const email = `web-authoring-${randomUUID()}@example.com`;
  const password = "web-authoring-test-password";
  const signup = await auth.auth.signUp({ email, password });
  expect(signup.error).toBeNull();
  expect(jar.size).toBeGreaterThan(0);
  await context.addCookies([...jar].map(([name, value]) => ({ name, value, url: baseURL })));
  await page.setViewportSize({ width: 390, height: 844 });
  await page.goto("/decks");
  await expect(
    page.getByRole("heading", { name: "첫 덱을 만들어 볼까요?", exact: true }),
  ).toBeVisible();
  await capture(page, "authoring-empty");
  await untilReacted(
    () => page.getByRole("button", { name: "새 덱 만들기", exact: true }).click(),
    () => page.getByRole("dialog").isVisible(),
  );
  await page.getByRole("button", { name: "직접 입력", exact: true }).click();
  await page.getByRole("textbox", { name: "이름", exact: true }).fill("영어 단어");
  await page.getByRole("button", { name: "만들기", exact: true }).click();
  await expect(page.getByRole("heading", { name: "영어 단어", exact: true })).toBeVisible();
  await capture(page, "authoring-deck");
  await page.getByRole("button", { name: "카드 추가", exact: true }).click();
  await page.getByRole("button", { name: "직접 입력", exact: true }).click();
  await page.getByRole("textbox", { name: "앞면 글 1", exact: true }).fill("apple");
  await page.getByRole("textbox", { name: "뒷면 글 1", exact: true }).fill("사과");
  await capture(page, "authoring-direct");
  await page.getByRole("button", { name: "저장", exact: true }).click();
  await expect(page.getByRole("dialog")).toHaveCount(0);
  await expect(page.getByRole("button", { name: "apple, 뒷면 가려짐", exact: true })).toBeVisible();
  const client = createClient(url, key, { auth: { persistSession: false } });
  expect((await client.auth.signInWithPassword({ email, password })).error).toBeNull();
  const read = await client
    .from("cards")
    .select("id,front,back,template,template_version,card_key,revision");
  expect(read.error).toBeNull();
  expect(read.data).toHaveLength(1);
  expect(read.data?.[0]).toMatchObject({
    template: "free",
    template_version: 1,
    card_key: "apple",
  });
  expect(Number(read.data?.[0]?.revision)).toBeGreaterThan(0);
  await page.getByRole("button", { name: "카드 추가", exact: true }).click();
  await page.getByRole("button", { name: "직접 입력", exact: true }).click();
  await page.getByRole("textbox", { name: "앞면 글 1", exact: true }).fill("ＡPPLE");
  await page.getByRole("textbox", { name: "뒷면 글 1", exact: true }).fill("different");
  await page.getByRole("button", { name: "저장", exact: true }).click();
  await expect(page.getByRole("dialog").getByRole("alert")).toHaveText(
    "이 덱에 이미 있는 카드예요",
  );
  await page.keyboard.press("Escape");
  expect((await client.from("cards").select("id")).data).toHaveLength(1);
  await page.getByRole("button", { name: "카드 추가", exact: true }).click();
  await page.getByRole("button", { name: "앨범에서 고르기", exact: true }).click();
  await expect(page.getByRole("status")).toContainText("이번 달");
  await expect(page.getByLabel("앨범에서 고르기", { exact: true })).toBeAttached();
  await page.keyboard.press("Escape");
  await expect(page.getByRole("button", { name: "카드 추가", exact: true })).toBeFocused();
});
