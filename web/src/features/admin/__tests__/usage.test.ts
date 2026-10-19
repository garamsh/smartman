import { describe, expect, it } from "vitest";

import { type BreakdownRow, summarizeUsage, unrecorded } from "../usage";

const haiku = "anthropic/claude-haiku-5.5"; // measured at $0.0018 a photo
const sonnet = "anthropic/claude-sonnet-5.5"; // measured at $0.0267
const row = (
  day: string,
  photos: number,
  plan: BreakdownRow["plan"],
  model: string | null,
  promptVersion: number | null,
): BreakdownRow => ({ day, photos, plan, model, promptVersion });

const rows: BreakdownRow[] = [
  row("2026-10-19", 10, "free", haiku, 2),
  row("2026-10-19", 2, "pro", sonnet, 2),
  row("2026-10-15", 5, "free", haiku, 1),
  row("2026-10-12", 4, null, null, null),
  row("2026-10-12", 3, "special", "vendor/unmeasured", 1),
  row("2026-09-01", 99, "free", haiku, 1),
];

describe("the overview's usage", () => {
  const usage = summarizeUsage(rows, "2026-10-19", haiku);

  it("costs each photo at its model's measured cost, and an unrecorded one at the Free plan's model", () => {
    expect(usage.totals.today).toEqual({ photos: 12, usd: 10 * 0.0018 + 2 * 0.0267, unpriced: 0 });
    expect(usage.days.find((day) => day.day === "2026-10-12")).toEqual({
      day: "2026-10-12",
      photos: 7,
      usd: 4 * 0.0018,
      unpriced: 3,
    });
    expect(usage.unpricedModels).toEqual(["vendor/unmeasured"]);
  });

  it("totals today, the last 7 days and the last 30, leaving out what came before", () => {
    expect(usage.totals.week.photos).toBe(17);
    expect(usage.totals.month.photos).toBe(24);
    expect(usage.days).toHaveLength(30);
    expect(usage.days[0]?.day).toBe("2026-09-20");
    expect(usage.days.at(-1)?.day).toBe("2026-10-19");
  });

  it("stacks each day's cost by plan, the plans in their order and the unrecorded photos last", () => {
    expect(usage.plans.series.map((series) => series.label)).toEqual([
      "무료",
      "프로",
      "스페셜",
      unrecorded,
    ]);
    expect(usage.plans.days.at(-1)?.values).toEqual({ free: 10 * 0.0018, pro: 2 * 0.0267 });
    expect(usage.plans.totals.special).toEqual({ photos: 3, usd: 0, unpriced: 3 });
  });

  it("stacks by model and sums by prompt version, the newest version first", () => {
    expect(usage.models.series.map((series) => series.key)).toEqual([
      haiku,
      sonnet,
      "vendor/unmeasured",
      unrecorded,
    ]);
    expect(usage.versions.map(({ version, amount }) => [version, amount.photos])).toEqual([
      [2, 12],
      [1, 8],
      [null, 4],
    ]);
  });

  it("prices no photo without a call record when the Free plan's model was never measured", () => {
    const unpriced = summarizeUsage(
      [row("2026-10-19", 4, null, null, null)],
      "2026-10-19",
      "vendor/unmeasured",
    );
    expect(unpriced.totals.today).toEqual({ photos: 4, usd: 0, unpriced: 4 });
  });
});
