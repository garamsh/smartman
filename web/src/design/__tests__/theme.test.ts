import { runInNewContext } from "node:vm";

import { afterEach, describe, expect, it, vi } from "vitest";

import {
  applyThemeChoice,
  readThemeChoice,
  storeThemeChoice,
  themeScript,
  themeStorageKey,
} from "../theme";

/** Runs the root layout's head script as the browser does, before anything else on the page. */
function runThemeScript() {
  runInNewContext(themeScript, { localStorage, document });
}

describe("the theme script", () => {
  afterEach(() => {
    localStorage.clear();
    delete document.documentElement.dataset.theme;
    vi.restoreAllMocks();
  });

  it.each(["light", "dark"] as const)("draws a stored %s choice on the root element", (choice) => {
    localStorage.setItem(themeStorageKey, choice);

    runThemeScript();

    expect(document.documentElement.dataset.theme).toBe(choice);
  });

  it("leaves the system's theme when nothing, or something unknown, is stored", () => {
    runThemeScript();
    expect(document.documentElement.dataset.theme).toBeUndefined();

    localStorage.setItem(themeStorageKey, "sepia");
    runThemeScript();
    expect(document.documentElement.dataset.theme).toBeUndefined();
  });

  it("leaves the system's theme, and throws nothing, when storage cannot be read", () => {
    localStorage.setItem(themeStorageKey, "dark");
    vi.spyOn(Storage.prototype, "getItem").mockImplementation(() => {
      throw new DOMException("blocked", "SecurityError");
    });

    expect(runThemeScript).not.toThrow();
    expect(document.documentElement.dataset.theme).toBeUndefined();
    expect(readThemeChoice(localStorage)).toBe("system");
  });
});

describe("a theme choice", () => {
  afterEach(() => {
    localStorage.clear();
    vi.restoreAllMocks();
  });

  it("is kept on this browser, and 시스템 removes what was kept", () => {
    expect(storeThemeChoice(localStorage, "dark")).toBeNull();
    expect(readThemeChoice(localStorage)).toBe("dark");

    expect(storeThemeChoice(localStorage, "system")).toBeNull();
    expect(localStorage.getItem(themeStorageKey)).toBeNull();
    expect(readThemeChoice(localStorage)).toBe("system");
  });

  it("says it was not kept when the browser refuses to store it", () => {
    vi.spyOn(Storage.prototype, "setItem").mockImplementation(() => {
      throw new DOMException("full", "QuotaExceededError");
    });

    expect(storeThemeChoice(localStorage, "light")).toBe("unstorable");
    expect(localStorage.getItem(themeStorageKey)).toBeNull();
  });

  it("is drawn by data-theme for 라이트 and 다크, and by its absence for 시스템", () => {
    const root = document.createElement("html");

    applyThemeChoice(root, "dark");
    expect(root.dataset.theme).toBe("dark");
    applyThemeChoice(root, "light");
    expect(root.dataset.theme).toBe("light");
    applyThemeChoice(root, "system");
    expect(root.hasAttribute("data-theme")).toBe(false);
  });
});
