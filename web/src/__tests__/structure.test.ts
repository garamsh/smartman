// @vitest-environment node
import { readdirSync } from "node:fs";
import path from "node:path";

import { describe, expect, it } from "vitest";

/** The entries docs/architecture/structure.md allows at the top of web/src/. */
const allowed = new Set([
  "app",
  "features",
  "design",
  "supabase",
  "styles",
  "testing",
  "__tests__",
  "env.ts",
  "proxy.ts",
]);

/** The entries of [names] outside the closed list. */
function unlisted(names: readonly string[]): string[] {
  return names.filter((name) => !allowed.has(name));
}

describe("web/src/", () => {
  const entries = readdirSync(path.join(import.meta.dirname, ".."));

  it("holds only the entries of the closed list", () => {
    // The listing reads the real folder: it holds the routes and this test's own folder.
    expect(entries).toEqual(expect.arrayContaining(["app", "__tests__"]));

    expect(unlisted(entries)).toEqual([]);
  });

  it("refuses an entry outside the closed list, and not a listed one", () => {
    expect(unlisted(["lib", "components", "utils.ts", "features", "env.ts"])).toEqual([
      "lib",
      "components",
      "utils.ts",
    ]);
    expect(unlisted([...allowed])).toEqual([]);
  });
});
