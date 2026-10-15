// @vitest-environment node
import { readFileSync } from "node:fs";
import path from "node:path";

import { describe, expect, it } from "vitest";

const config: unknown = JSON.parse(
  readFileSync(path.join(import.meta.dirname, "../../vercel.json"), "utf8"),
);

describe("web/vercel.json", () => {
  it("runs the functions in hnd1, beside the Supabase project in Tokyo, and sets nothing else", () => {
    // Only the region: any other key would be behaviour the container, which ignores this file, lacks.
    expect(config).toEqual({
      $schema: "https://openapi.vercel.sh/vercel.json",
      regions: ["hnd1"],
    });
  });
});
