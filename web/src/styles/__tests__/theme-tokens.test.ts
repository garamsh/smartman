// @vitest-environment node
import { readFileSync } from "node:fs";
import path from "node:path";

import { describe, expect, it } from "vitest";

const root = path.join(import.meta.dirname, "../../../..");
const themeDart = readFileSync(path.join(root, "app/lib/shared/theme.dart"), "utf8");
const globalsCss = readFileSync(path.join(root, "web/src/styles/globals.css"), "utf8");

/** The colours of one `AppColors` set in theme.dart, by token name, as lowercase #rrggbb. */
function dartColors(set: "light" | "dark"): Map<string, string> {
  const body = new RegExp(`static const ${set} = AppColors\\(([^;]*)\\);`).exec(themeDart)?.[1];
  if (body === undefined) throw new Error(`theme.dart has no AppColors.${set}`);
  return new Map(
    [...body.matchAll(/(\w+): Color\(0xFF([0-9A-Fa-f]{6})\)/g)].map(([, name, hex]) => [
      String(name).replace(/[A-Z]/g, (letter) => `-${letter.toLowerCase()}`),
      `#${String(hex).toLowerCase()}`,
    ]),
  );
}

/** The `--color-*` tokens a CSS block declares, by token name. */
function cssColors(block: string): Map<string, string> {
  return new Map(
    [...block.matchAll(/--color-([\w-]+):\s*(#[0-9a-f]{6});/g)].map(([, name, hex]) => [
      String(name),
      String(hex),
    ]),
  );
}

const lightCss = /@theme \{([^}]*)\}/.exec(globalsCss)?.[1] ?? "";
const darkCss = /prefers-color-scheme: dark\)\s*\{\s*:root \{([^}]*)\}/.exec(globalsCss)?.[1] ?? "";

describe("the web theme's colour tokens", () => {
  it("are the light tokens of app/lib/shared/theme.dart", () => {
    expect(dartColors("light").size).toBe(13);
    expect(cssColors(lightCss)).toEqual(dartColors("light"));
  });

  it("are the dark tokens of app/lib/shared/theme.dart under prefers-color-scheme: dark", () => {
    expect(dartColors("dark").size).toBe(13);
    expect(cssColors(darkCss)).toEqual(dartColors("dark"));
  });
});
