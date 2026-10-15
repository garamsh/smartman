import { readFileSync } from "node:fs";
import path from "node:path";

import { describe, expect, it } from "vitest";

import { schedule } from "../engine";

type Step = {
  fuzz_factor: number | null;
  rating: number;
  at: number;
  stability: number;
  difficulty: number;
  due: number;
};

/** The engine's reference values, which py-fsrs 6.3.2 wrote (engine.md). */
const reference = JSON.parse(
  readFileSync(
    path.join(import.meta.dirname, "../../../../../engine/tests/fixtures/reference.json"),
    "utf8",
  ),
) as { fuzzed_sequences: { name: string; seed: number; reviews: Step[] }[] };

const day = 86_400_000;

describe("the engine module, loaded as the browser loads it", () => {
  it("reviews a stored state as the reference values do, fuzz included", async () => {
    const sequence = reference.fuzzed_sequences.find(
      ({ name, seed }) => name === "good-on-due" && seed === 1,
    );
    const [first, second] = sequence?.reviews ?? [];
    if (!first || !second || second.fuzz_factor === null) throw new Error("no fuzzed step");

    const scheduled = await schedule(
      {
        stability: first.stability,
        difficulty: first.difficulty,
        lastReview: first.at * 1000,
        due: first.due * 1000,
      },
      [{ answer: "know", reviewedAt: second.at * 1000, fuzzFactor: second.fuzz_factor }],
    );

    if (!("state" in scheduled)) throw new Error(`refused: ${JSON.stringify(scheduled)}`);
    expect(scheduled.state.stability).toBeCloseTo(second.stability, 9);
    expect(scheduled.state.difficulty).toBeCloseTo(second.difficulty, 9);
    expect(scheduled.state.lastReview).toBe(second.at * 1000);
    expect(scheduled.state.due).toBe(second.due * 1000);
  });

  it("returns a refused review as its typed engine error", async () => {
    const before = { stability: 3, difficulty: 5, lastReview: 10 * day, due: 13 * day };

    const refused = await schedule(before, [
      { answer: "know", reviewedAt: 10 * day - 1000, fuzzFactor: 0.5 },
    ]);
    // Control: a review at the same instant as the last is accepted.
    const accepted = await schedule(before, [
      { answer: "know", reviewedAt: 10 * day, fuzzFactor: 0.5 },
    ]);

    expect(refused).toEqual({
      error: { kind: "reviewBeforeLastReview", lastReview: 864_000n, review: 863_999n },
    });
    expect(accepted).toHaveProperty("state");
  });
});
