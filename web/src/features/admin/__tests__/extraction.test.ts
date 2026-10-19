// @vitest-environment node
import { readFileSync } from "node:fs";
import path from "node:path";

import { describe, expect, it } from "vitest";

import { dailyExtractionLimit, estimatedCost, estimatedUsdPerPhoto } from "../extraction";

const root = path.join(import.meta.dirname, "../../../../..");
const functionLimit = (source: string) =>
  Number(/^export const DAILY_EXTRACTION_LIMIT = (\d+);$/m.exec(source)?.[1]);

describe("the admin area's extraction figures", () => {
  it("state the daily limit extract-cards enforces", () => {
    const source = readFileSync(
      path.join(root, "supabase/functions/extract-cards/supabase.ts"),
      "utf8",
    );
    expect(functionLimit(source)).toBe(dailyExtractionLimit);
    // Control: the comparison sees a changed limit.
    expect(
      functionLimit(
        source.replace(/DAILY_EXTRACTION_LIMIT = \d+;/, "DAILY_EXTRACTION_LIMIT = 31;"),
      ),
    ).not.toBe(dailyExtractionLimit);
  });

  it("price photos at the one per-photo cost, in dollars with four decimals", () => {
    expect(estimatedUsdPerPhoto).toBe(0.0018);
    expect(estimatedCost(0)).toBe("$0.0000");
    expect(estimatedCost(30)).toBe("$0.0540");
  });
});
