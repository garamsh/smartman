// @vitest-environment node
import { readFileSync } from "node:fs";
import path from "node:path";

import { describe, expect, it } from "vitest";

const globalsCss = readFileSync(path.join(import.meta.dirname, "../globals.css"), "utf8");

/** The `--color-*` tokens of a CSS block, by name. */
function colours(block: string): Map<string, string> {
  return new Map(
    [...block.matchAll(/--color-([\w-]+):\s*(#[0-9a-f]{6});/g)].map(([, name, hex]) => [
      String(name),
      String(hex),
    ]),
  );
}

const themes = {
  light: colours(/@theme \{([^}]*)\}/.exec(globalsCss)?.[1] ?? ""),
  dark: colours(/:root\[data-theme="dark"\] \{([^}]*--color[^}]*)\}/.exec(globalsCss)?.[1] ?? ""),
};

/** WCAG 2.2's relative luminance of #rrggbb. */
function luminance(hex: string): number {
  const [r = 0, g = 0, b = 0] = [1, 3, 5].map((at) => {
    const channel = parseInt(hex.slice(at, at + 2), 16) / 255;
    return channel <= 0.04045 ? channel / 12.92 : ((channel + 0.055) / 1.055) ** 2.4;
  });
  return 0.2126 * r + 0.7152 * g + 0.0722 * b;
}

/** WCAG 2.2's contrast ratio between two colours. */
function contrast(a: string, b: string): number {
  const [light, dark] = [luminance(a), luminance(b)].sort((x, y) => y - x);
  return ((light ?? 0) + 0.05) / ((dark ?? 0) + 0.05);
}

/**
 * The text and its ground on the login, account and empty home pages and the shell's menus and
 * pages, by where they appear.
 */
const pairs: [string, string, string][] = [
  ["the welcome sentence on the panel", "ink-2", "ground"],
  ["the consent line on the surface", "muted", "surface"],
  ["the legal links on the surface", "ink-2", "surface"],
  ["a sign-in error on the surface", "dont-know-text", "surface"],
  ["Google's label on its fill", "google-label", "google-fill"],
  ["an unchecked theme on its track", "ink-2", "ground"],
  ["the checked theme on its segment", "ink", "raised"],
  ["the empty home's sentence on the ground", "muted", "ground"],
  ["the empty home's title on the ground", "ink", "ground"],
  ["the side menu's other pages on the surface", "ink-2", "surface"],
  ["the side menu's current page on its tint", "ink", "brand-tint"],
  ["the tab bar's other pages on the surface", "muted", "surface"],
  ["the today card's text on the navy", "on-hero", "hero"],
  ["the today card's button on white", "brand", "on-hero"],
  ["the forecast's days and a deck's progress on the surface", "muted", "surface"],
  ["the date and the breadcrumb on the ground", "muted", "ground"],
];

describe("the text the login, account and empty home pages draw", () => {
  it("is measured on a pair known to fail", () => {
    // Control: black on white is 21:1, and #777 on white falls short.
    expect(contrast("#000000", "#ffffff")).toBeCloseTo(21, 5);
    expect(contrast("#777777", "#ffffff")).toBeLessThan(4.5);
  });

  it.each(["light", "dark"] as const)("meets WCAG AA, 4.5:1, in the %s theme", (theme) => {
    const set = themes[theme];
    expect(set.size).toBeGreaterThan(25);
    for (const [where, text, ground] of pairs) {
      const ratio = contrast(set.get(text) ?? "", set.get(ground) ?? "");
      expect({ where, aa: ratio >= 4.5 }).toEqual({ where, aa: true });
    }
  });
});

/**
 * The text the study screen draws on its grades, its answer buttons and its guide, by where it
 * appears.
 */
const studyPairs: [string, string, string][] = [
  ["the guide's size on the ground", "ink", "ground"],
  ["the guide's lines on the ground", "ink-2", "ground"],
  ["a 안다 card's front", "ink", "know-card"],
  ["a 안다 card's back", "ink-2", "know-card"],
  ["a 모른다 card's front", "ink", "dont-know-card"],
  ["a 모른다 card's back", "ink-2", "dont-know-card"],
  ["the 안다 chip's word", "on-know", "know"],
  ["the 모른다 chip's word", "on-dont-know-text", "dont-know-text"],
  ["the 안다 button's word", "on-know-tint", "tint-green"],
  ["the 모른다 button's word", "on-dont-know-tint", "tint-red"],
];

/** The marks the study screen draws, at 3:1 against what is around them. */
const studyMarks: [string, string, string][] = [
  ["the 안다 chip on its card", "know", "know-card"],
  ["the 안다 chip on the ground", "know", "ground"],
  ["the 모른다 chip on its card", "dont-know-text", "dont-know-card"],
  ["the 모른다 chip on the ground", "dont-know-text", "ground"],
  ["the streak's flame on the completion card", "streak", "surface"],
];

describe("the study screen's grades, answer buttons and streak", () => {
  it.each(["light", "dark"] as const)(
    "meet WCAG AA, 4.5:1 for text and 3:1 for marks, in the %s theme",
    (theme) => {
      const set = themes[theme];
      for (const [where, text, ground] of studyPairs) {
        const ratio = contrast(set.get(text) ?? "#000000", set.get(ground) ?? "#000000");
        expect({ where, aa: ratio >= 4.5 }).toEqual({ where, aa: true });
      }
      for (const [where, mark, ground] of studyMarks) {
        const ratio = contrast(set.get(mark) ?? "#000000", set.get(ground) ?? "#000000");
        expect({ where, aa: ratio >= 3 }).toEqual({ where, aa: true });
      }
    },
  );
});
