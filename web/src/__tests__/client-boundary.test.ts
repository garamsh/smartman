// @vitest-environment node
import { existsSync, readdirSync, readFileSync, statSync } from "node:fs";
import path from "node:path";

import { describe, expect, it } from "vitest";

/**
 * `next build` refuses a server-only module reached from a Client Component (stack-nextjs §13),
 * which neither tsc nor Vitest checks. This walks each `"use client"` module's value imports the
 * way the bundler does and names any server-only module it reaches.
 */

const src = path.join(import.meta.dirname, "..");

/** A module's value imports and re-exports; `import type` and `export type` are erased. */
const imports = /^\s*(?:import|export)\s+(?!type\b)(?:[^'"]*?\sfrom\s+)?["']([^"']+)["']/gm;

function read(file: string): string {
  return readFileSync(file, "utf8");
}

/** The source file [spec] names from [from], or null for a package. */
function resolve(spec: string, from: string): string | null {
  const base = spec.startsWith("@/")
    ? path.join(src, spec.slice(2))
    : spec.startsWith(".")
      ? path.join(path.dirname(from), spec)
      : null;
  if (base === null) return null;
  const candidates = [".ts", ".tsx", "/index.ts", "/index.tsx"].map((end) => base + end);
  return [base, ...candidates].find((file) => existsSync(file) && statSync(file).isFile()) ?? null;
}

/** Every source module under web/src/ but tests and test helpers. */
function modules(dir = src): string[] {
  return readdirSync(dir).flatMap((name) => {
    const file = path.join(dir, name);
    if (statSync(file).isDirectory()) {
      return name === "__tests__" || name === "testing" ? [] : modules(file);
    }
    return /\.tsx?$/.test(name) ? [file] : [];
  });
}

const directive = (file: string, name: string) =>
  new RegExp(`^\\s*["']${name}["']`).test(read(file));

/**
 * The chain from [root] to the first server-only module its value imports reach, or null. A
 * `"use server"` module is not followed: the bundler replaces it with references.
 */
function serverOnlyChain(root: string): string[] | null {
  const seen = new Set([root]);
  const queue: string[][] = [[root]];
  for (let chain = queue.shift(); chain; chain = queue.shift()) {
    const file = chain.at(-1) ?? root;
    if (/^\s*import\s+["']server-only["']/m.test(read(file))) return chain;
    if (file !== root && directive(file, "use server")) continue;
    for (const [, spec] of read(file).matchAll(imports)) {
      const next = spec === undefined ? null : resolve(spec, file);
      if (next && !seen.has(next)) {
        seen.add(next);
        queue.push([...chain, next]);
      }
    }
  }
  return null;
}

const relative = (chain: string[]) => chain.map((file) => path.relative(src, file)).join(" -> ");

describe("a client module", () => {
  it("reaches no server-only module through its imports", () => {
    const clients = modules().filter((file) => directive(file, "use client"));
    expect(clients.length).toBeGreaterThan(0);

    const reached = clients.flatMap((file) => {
      const chain = serverOnlyChain(file);
      return chain ? [relative(chain)] : [];
    });

    expect(reached).toEqual([]);
  });

  it("is told apart from a server one, which does reach one", () => {
    // Control: decks' entry point, which Server Components read, reaches its server-only library
    // read, so the walk and the server-only check work.
    const chain = serverOnlyChain(path.join(src, "features/decks/index.ts")) ?? [];
    expect(relative(chain)).toBe("features/decks/index.ts -> features/decks/read-library.ts");
  });
});
