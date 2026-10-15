// @vitest-environment node
import { readFileSync } from "node:fs";
import path from "node:path";

import { describe, expect, it } from "vitest";

const root = path.join(import.meta.dirname, "../../../..");
const themeDart = readFileSync(path.join(root, "app/lib/shared/theme.dart"), "utf8");
const globalsCss = readFileSync(path.join(root, "web/src/styles/globals.css"), "utf8");

/** A Dart name in kebab case, as the web's tokens spell it: `deckTitle` is `deck-title`. */
function kebab(name: string): string {
  return name.replace(/[A-Z]|\d+/g, (part) => `-${part.toLowerCase()}`);
}

/** The body of `abstract final class [name]` in theme.dart. */
function dartClass(name: string): string {
  const body = new RegExp(`abstract final class ${name} \\{([\\s\\S]*?)\\n\\}`).exec(
    themeDart,
  )?.[1];
  if (body === undefined) throw new Error(`theme.dart has no ${name}`);
  return body;
}

/** The colours of one `AppColors` set in theme.dart, by token name, as lowercase #rrggbb. */
function dartColors(set: "light" | "dark"): Map<string, string> {
  const body = new RegExp(`static const ${set} = AppColors\\(([^;]*)\\);`).exec(themeDart)?.[1];
  if (body === undefined) throw new Error(`theme.dart has no AppColors.${set}`);
  return new Map(
    [...body.matchAll(/(\w+): Color\(0xFF([0-9A-Fa-f]{6})\)/g)].map(([, name, hex]) => [
      kebab(String(name)),
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
    expect(dartColors("light").size).toBe(25);
    expect(cssColors(lightCss)).toEqual(dartColors("light"));
  });

  it("are the dark tokens of app/lib/shared/theme.dart under prefers-color-scheme: dark", () => {
    expect(dartColors("dark").size).toBe(25);
    expect(cssColors(darkCss)).toEqual(dartColors("dark"));
  });
});

/** The radii of `AppRadius` in theme.dart, by token name, in logical pixels. */
function dartRadii(): Map<string, number> {
  const body = /abstract final class AppRadius \{([^}]*)\}/.exec(themeDart)?.[1];
  if (body === undefined) throw new Error("theme.dart has no AppRadius");
  return new Map(
    [...body.matchAll(/static const (\w+) = ([\d.]+);/g)].map(([, name, value]) => [
      String(name),
      Number(value),
    ]),
  );
}

describe("the web theme's radius tokens", () => {
  it("are the radii of app/lib/shared/theme.dart's AppRadius", () => {
    const radii = new Map(
      [...lightCss.matchAll(/--radius-([\w-]+):\s*([\d.]+)px;/g)].map(([, name, value]) => [
        String(name),
        Number(value),
      ]),
    );
    // Control: both sides read their tokens, the card's radius among them.
    expect(dartRadii().get("card")).toBe(24);
    expect([...radii.keys()].sort()).toEqual([
      "button",
      "card",
      "field",
      "panel",
      "previous",
      "row",
      "sheet",
    ]);

    for (const [name, value] of radii) {
      expect({ name, value }).toEqual({ name, value: dartRadii().get(name) });
    }
  });
});

/** A type style's size, line height and letter spacing in pixels, and its weight. */
type TypeStyle = { size: number; lineHeight: number; weight: number; letterSpacing: number };

/** The styles of `AppType` in theme.dart, by token name. */
function dartType(): Map<string, TypeStyle> {
  return new Map(
    [...dartClass("AppType").matchAll(/static const (\w+) = TextStyle\(([^)]*)\);/g)].map(
      ([, name, body = ""]) => {
        const size = Number(/fontSize: ([\d.]+)/.exec(body)?.[1]);
        const [, over, under] = /height: ([\d.]+) \/ ([\d.]+)/.exec(body) ?? [];
        return [
          kebab(String(name)),
          {
            size,
            lineHeight: Math.round((Number(over) / Number(under)) * size * 100) / 100,
            weight: Number(/fontWeight: FontWeight\.w(\d+)/.exec(body)?.[1]),
            letterSpacing: Number(/letterSpacing: (-?[\d.]+)/.exec(body)?.[1] ?? 0),
          },
        ];
      },
    ),
  );
}

/** The `--text-*` styles `@theme` declares, by token name; an absent letter spacing is 0. */
function cssType(): Map<string, TypeStyle> {
  const value = (name: string, part: string) =>
    new RegExp(`--text-${name}${part}:\\s*(-?[\\d.]+)(?:px)?;`).exec(lightCss)?.[1];
  return new Map(
    [...lightCss.matchAll(/--text-([a-z]+(?:-[a-z]+)*):\s*[\d.]+px;/g)].map(([, name = ""]) => [
      name,
      {
        size: Number(value(name, "")),
        lineHeight: Number(value(name, "--line-height")),
        weight: Number(value(name, "--font-weight")),
        letterSpacing: Number(value(name, "--letter-spacing") ?? 0),
      },
    ]),
  );
}

describe("the web theme's type tokens", () => {
  it("are the styles of app/lib/shared/theme.dart's AppType: size, line height, weight and tracking", () => {
    // Control: both sides read every style, the question's tracking among them.
    expect(dartType().size).toBe(14);
    expect(dartType().get("question")).toEqual({
      size: 30,
      lineHeight: 38,
      weight: 800,
      letterSpacing: -0.6,
    });
    expect(cssType()).toEqual(dartType());
  });
});

/** The `static const` numbers of [body], by name, a name standing for another's value resolved. */
function dartNumbers(body: string): Map<string, number> {
  const numbers = new Map<string, number>();
  for (const [, name = "", value = ""] of body.matchAll(/static const (\w+) = ([\w.]+);/g)) {
    const resolved = /^[\d.]+$/.test(value) ? Number(value) : numbers.get(value);
    if (resolved !== undefined) numbers.set(name, resolved);
  }
  return numbers;
}

/** The `--spacing-*` tokens `@theme` declares, by name, in pixels. */
const cssSpacing = new Map(
  [...lightCss.matchAll(/--spacing-([\w-]+):\s*([\d.]+)px;/g)].map(([, name, value]) => [
    String(name),
    Number(value),
  ]),
);

/** The spacing tokens named for one of AppSpace's named gaps; every other is a size. */
const namedGaps = ["gutter", "row-gap", "section-gap"];

describe("the web theme's spacing tokens", () => {
  it("make every step of app/lib/shared/theme.dart's AppSpace a whole number of the 4 px unit", () => {
    const steps = dartNumbers(dartClass("AppSpace"));
    // Control: the steps and the named gaps are read.
    expect(steps.get("s40")).toBe(40);
    expect(steps.get("sectionGap")).toBe(28);
    expect(/--spacing:\s*([\d.]+)px;/.exec(lightCss)?.[1]).toBe("4");

    for (const [name, value] of steps) {
      expect({ name, steps: value / 4 }).toEqual({ name, steps: Math.round(value / 4) });
    }
  });

  it("name AppSpace's gutter, row gap and section gap with their values", () => {
    const steps = dartNumbers(dartClass("AppSpace"));
    for (const name of namedGaps) {
      expect({ name, value: cssSpacing.get(name) }).toEqual({
        name,
        value: steps.get(name.replace(/-(\w)/g, (_, letter: string) => letter.toUpperCase())),
      });
    }
  });
});

describe("the web theme's size tokens", () => {
  it("are the sizes of app/lib/shared/theme.dart's AppSize under the same names", () => {
    const sizes = new Map(
      [...dartNumbers(dartClass("AppSize"))].map(([name, value]) => [kebab(name), value]),
    );
    const web = [...cssSpacing].filter(([name]) => !namedGaps.includes(name));
    // Control: both sides read their sizes, the button's height among them.
    expect(sizes.get("button")).toBe(52);
    expect(web.length).toBe(14);

    for (const [name, value] of web) {
      expect({ name, value }).toEqual({ name, value: sizes.get(name) });
    }
  });
});
