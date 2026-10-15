import { expect, test } from "@playwright/test";

test.describe("signed out", () => {
  test("opening the app lands on /login, which offers Google sign-in", async ({ page }) => {
    await page.goto("/");

    await expect(page).toHaveURL(/\/login$/);
    await expect(page.getByRole("heading", { name: "smartman", exact: true })).toBeVisible();
    await expect(page.getByRole("button", { name: "Google로 로그인", exact: true })).toBeEnabled();
  });

  test("Google sign-in leaves for Supabase Auth with this origin's /auth/callback", async ({
    page,
  }) => {
    const authorize = page.waitForRequest(/\/auth\/v1\/authorize\?/);
    // The request is stopped here: the real Google consent screen is not part of the test.
    await page.route(/\/auth\/v1\/authorize\?/, (route) => route.abort());
    await page.goto("/login");

    await page.getByRole("button", { name: "Google로 로그인", exact: true }).click();

    const url = new URL((await authorize).url());
    expect(url.searchParams.get("provider")).toBe("google");
    expect(url.searchParams.get("redirect_to")).toBe(new URL("/auth/callback", page.url()).href);
  });

  test("the theme follows the system's dark mode", async ({ page }) => {
    await page.emulateMedia({ colorScheme: "light" });
    await page.goto("/login");
    await expect(page.locator("body")).toHaveCSS("background-color", "rgb(238, 241, 245)");

    await page.emulateMedia({ colorScheme: "dark" });
    await expect(page.locator("body")).toHaveCSS("background-color", "rgb(15, 17, 21)");
  });

  test("/api/health answers 200 without a session", async ({ request }) => {
    const response = await request.get("/api/health");

    expect(response.status()).toBe(200);
    expect(await response.json()).toEqual({ status: "ok" });
  });
});
