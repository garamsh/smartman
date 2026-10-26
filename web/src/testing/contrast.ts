import { readFileSync } from "node:fs";
import path from "node:path";

import { expect } from "vitest";

const globalsCss = readFileSync(path.join(import.meta.dirname, "../styles/globals.css"), "utf8");

/** The `--color-*` tokens of a CSS block, by name. */
function colours(block: string): Map<string, string> {
  return new Map(
    [...block.matchAll(/--color-([\w-]+):\s*(#[0-9a-f]{6});/g)].map(([, name, hex]) => [
      String(name),
      String(hex),
    ]),
  );
}

/** The colour tokens of globals.css in each theme. */
export const themes = {
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
export function contrast(a: string, b: string): number {
  const [light, dark] = [luminance(a), luminance(b)].sort((x, y) => y - x);
  return ((light ?? 0) + 0.05) / ((dark ?? 0) + 0.05);
}

/** [layer] at [share] over the opaque [ground], composited in sRGB. */
export function layered(ground: string, layer: string, share: number): string {
  return `#${[1, 3, 5]
    .map((at) => {
      const under = parseInt(ground.slice(at, at + 2), 16);
      const over = parseInt(layer.slice(at, at + 2), 16);
      return Math.round(under * (1 - share) + over * share)
        .toString(16)
        .padStart(2, "0");
    })
    .join("")}`;
}

/** The colour token and opacity a Tailwind class of [prefix] names on [element], if any. */
function tokenOf(element: Element, prefix: "text" | "bg") {
  for (const name of element.classList) {
    const [, token, opacity] = new RegExp(`^${prefix}-([\\w-]+?)(?:/(\\d+))?$`).exec(name) ?? [];
    if (token && themes.light.has(token)) {
      return { token, share: opacity ? Number(opacity) / 100 : 1 };
    }
  }
  return undefined;
}

/**
 * Expects every text in [card], outside its links and buttons, at 4.5:1 or more on the card's
 * fill in both themes, each text in the colour its nearest `text-` token class gives it. Unlike a
 * check of what the browser draws, this also fails text in the colour of its ground, which leaves
 * nothing on screen to measure.
 */
export function expectTextReadable(card: HTMLElement) {
  const fill = tokenOf(card, "bg")?.token;
  expect(fill, "the card's fill").toBeDefined();
  const walker = document.createTreeWalker(card, NodeFilter.SHOW_TEXT);
  const texts: { text: string; token: string; share: number }[] = [];
  for (let node = walker.nextNode(); node; node = walker.nextNode()) {
    const text = node.textContent?.trim() ?? "";
    const parent = node.parentElement;
    const control = parent?.closest("a, button");
    if (!text || !parent || (control && card.contains(control))) continue;
    let colour;
    for (
      let element: Element | null = parent;
      element && !colour;
      element = element.parentElement
    ) {
      colour = tokenOf(element, "text");
      if (element === card) break;
    }
    expect(colour, `the colour of "${text}"`).toBeDefined();
    if (colour) texts.push({ text, ...colour });
  }
  expect(texts).not.toHaveLength(0);
  for (const [theme, set] of Object.entries(themes)) {
    const ground = set.get(fill ?? "") ?? "";
    for (const { text, token, share } of texts) {
      const ratio = contrast(layered(ground, set.get(token) ?? "", share), ground);
      expect({ text, token, fill, theme, aa: ratio >= 4.5 }).toEqual({
        text,
        token,
        fill,
        theme,
        aa: true,
      });
    }
  }
}
