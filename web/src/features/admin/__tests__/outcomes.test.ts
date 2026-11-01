import { describe, expect, it } from "vitest";

import { failureRate, type OutcomeDay, summarizeOutcomes } from "../outcomes";

const day = (date: string, promptVersion: number, counts: Partial<OutcomeDay>): OutcomeDay => ({
  day: date,
  promptVersion,
  calls: 0,
  ok: 0,
  noCards: 0,
  invalidOutput: 0,
  modelError: 0,
  retried: 0,
  recovered: 0,
  unrecorded: 0,
  ...counts,
});

const rows = [
  day("2026-11-01", 10, { calls: 20, ok: 17, noCards: 1, invalidOutput: 1, modelError: 1 }),
  day("2026-11-01", 9, { calls: 5, ok: 5, retried: 1, recovered: 1 }),
  day("2026-10-20", 9, { calls: 10, ok: 6, invalidOutput: 4, retried: 4, unrecorded: 2 }),
  // The day before the 30-day window.
  day("2026-10-02", 9, { calls: 100, modelError: 100 }),
];

describe("the outcomes' summary", () => {
  const summary = summarizeOutcomes(rows, "2026-11-01");

  it("sums the 30 days that end today, and leaves out a day before them", () => {
    expect(summary.total).toEqual({
      calls: 35,
      ok: 28,
      noCards: 1,
      invalidOutput: 5,
      modelError: 1,
      retried: 5,
      recovered: 1,
      unrecorded: 2,
    });
    expect(failureRate(summary.total)).toBeCloseTo(6 / 35);
  });

  it("gives every day of the window, oldest first, each version of a day summed", () => {
    expect(summary.days).toHaveLength(30);
    expect(summary.days[0]?.day).toBe("2026-10-03");
    expect(summary.days.at(-1)).toMatchObject({ day: "2026-11-01", counts: { calls: 25 } });
    // A day without a call has no rate, which is not a rate of 0.
    const quiet = summary.days.find(({ day: date }) => date === "2026-10-21");
    expect(quiet?.counts.calls).toBe(0);
    expect(failureRate(quiet?.counts ?? summary.total)).toBeNull();
    const busy = summary.days.find(({ day: date }) => date === "2026-11-01");
    expect(failureRate(busy?.counts ?? summary.total)).toBeCloseTo(2 / 25);
  });

  it("gives each version's counts over the window, newest version first", () => {
    expect(summary.versions.map(({ version, counts }) => [version, counts.calls])).toEqual([
      [10, 20],
      [9, 15],
    ]);
    expect(failureRate(summary.versions[1]?.counts ?? summary.total)).toBeCloseTo(4 / 15);
  });
});
