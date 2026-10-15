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
    const origin = new URL(page.url()).origin;

    await page.getByRole("button", { name: "Google로 로그인", exact: true }).click();

    const url = new URL((await authorize).url());
    expect(url.searchParams.get("provider")).toBe("google");
    expect(url.searchParams.get("redirect_to")).toBe(`${origin}/auth/callback`);
  });

  test("the theme follows the system's dark mode", async ({ page }) => {
    await page.emulateMedia({ colorScheme: "light" });
    await page.goto("/login");
    await expect(page.locator("body")).toHaveCSS("background-color", "rgb(244, 246, 250)");

    await page.emulateMedia({ colorScheme: "dark" });
    await expect(page.locator("body")).toHaveCSS("background-color", "rgb(14, 20, 36)");
  });

  test("the icons and the manifest are served without a session", async ({ request }) => {
    for (const path of ["/favicon.svg", "/favicon-32.png", "/apple-touch-icon.png"]) {
      const response = await request.get(path, { maxRedirects: 0 });
      expect({ path, status: response.status() }).toEqual({ path, status: 200 });
    }
    const manifest = await request.get("/manifest.webmanifest", { maxRedirects: 0 });
    expect(manifest.status()).toBe(200);
    expect(await manifest.json()).toMatchObject({ theme_color: "#1F2A44" });
    for (const { src } of ((await manifest.json()) as { icons: { src: string }[] }).icons) {
      const icon = await request.get(src, { maxRedirects: 0 });
      expect({ src, status: icon.status() }).toEqual({ src, status: 200 });
    }
  });

  test("/api/health answers 200 without a session", async ({ request }) => {
    const response = await request.get("/api/health");

    expect(response.status()).toBe(200);
    expect(await response.json()).toEqual({ status: "ok" });
  });
});
