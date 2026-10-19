import { usdPerPhoto } from "./model-costs";
import type { PlanId } from "./read-admin";

/** One row of the server's breakdown: a UTC day's photos served by one plan, model and version. */
export type BreakdownRow = {
  day: string;
  /** Null for a photo counted before calls were recorded (ADR 0073). */
  plan: PlanId | null;
  model: string | null;
  promptVersion: number | null;
  photos: number;
};

/** Photos and their estimated cost; `unpriced` photos were served by a model never measured. */
export type Amount = { photos: number; usd: number; unpriced: number };

/** One series of a stacked chart: its key in each day's values, and its name. */
export type Series = { key: string; label: string };

/** Each day's estimated cost per series, oldest first, with the series in drawing order. */
export type Stack = {
  series: Series[];
  days: { day: string; values: Record<string, number> }[];
  totals: Record<string, Amount>;
};

/** The usage the overview charts. */
export type Usage = {
  days: ({ day: string } & Amount)[];
  totals: { today: Amount; week: Amount; month: Amount };
  plans: Stack;
  models: Stack;
  versions: { version: number | null; amount: Amount }[];
  /** The models with photos and no measured cost. */
  unpricedModels: string[];
  /** The model a photo without a call record is costed at: the Free plan's. */
  unrecordedModel: string | null;
};

const planNames: Record<PlanId, string> = { free: "무료", pro: "프로", special: "스페셜" };
/** The series of the photos counted before calls were recorded. */
export const unrecorded = "기록 전";

/** The UTC day [offset] days from [today], as YYYY-MM-DD. */
function dayFrom(today: string, offset: number): string {
  return new Date(Date.parse(`${today}T00:00:00Z`) + offset * 86_400_000)
    .toISOString()
    .slice(0, 10);
}

const empty = (): Amount => ({ photos: 0, usd: 0, unpriced: 0 });

function add(amount: Amount, photos: number, usd: number | null): void {
  amount.photos += photos;
  if (usd === null) amount.unpriced += photos;
  else amount.usd += photos * usd;
}

/**
 * The last [span] UTC days' usage ending [today], from the server's [rows]: each photo costed at
 * its model's measured cost, and a photo without a call record at [freeModel]'s.
 */
export function summarizeUsage(
  rows: readonly BreakdownRow[],
  today: string,
  freeModel: string | null,
  span = 30,
): Usage {
  const dayList = Array.from({ length: span }, (_, index) => dayFrom(today, index - span + 1));
  const days = new Map(dayList.map((day) => [day, empty()]));
  const weekStart = dayFrom(today, -6);
  const totals = { today: empty(), week: empty(), month: empty() };
  const plans = new Map<string, Series>();
  const models = new Map<string, Series>();
  const planDays = new Map<string, Record<string, number>>(dayList.map((day) => [day, {}]));
  const modelDays = new Map<string, Record<string, number>>(dayList.map((day) => [day, {}]));
  const planTotals: Record<string, Amount> = {};
  const modelTotals: Record<string, Amount> = {};
  const versions = new Map<number | null, Amount>();
  const unpriced = new Set<string>();
  for (const row of rows) {
    const dayAmount = days.get(row.day);
    if (dayAmount === undefined) continue;
    const model = row.model ?? freeModel;
    const usd = model === null ? null : usdPerPhoto(model);
    if (usd === null && model !== null) unpriced.add(model);
    add(dayAmount, row.photos, usd);
    add(totals.month, row.photos, usd);
    if (row.day >= weekStart) add(totals.week, row.photos, usd);
    if (row.day === today) add(totals.today, row.photos, usd);
    const planKey = row.plan ?? unrecorded;
    const modelKey = row.model ?? unrecorded;
    plans.set(planKey, {
      key: planKey,
      label: row.plan === null ? unrecorded : planNames[row.plan],
    });
    models.set(modelKey, { key: modelKey, label: modelKey });
    for (const [perDay, key, sums] of [
      [planDays, planKey, planTotals],
      [modelDays, modelKey, modelTotals],
    ] as const) {
      const values = perDay.get(row.day);
      if (values !== undefined) values[key] = (values[key] ?? 0) + row.photos * (usd ?? 0);
      add((sums[key] ??= empty()), row.photos, usd);
    }
    const version = versions.get(row.promptVersion) ?? empty();
    add(version, row.photos, usd);
    versions.set(row.promptVersion, version);
  }
  const ordered = (series: Map<string, Series>, rank: (key: string) => number) =>
    [...series.values()].toSorted(
      (a, b) => rank(a.key) - rank(b.key) || a.key.localeCompare(b.key),
    );
  const planRank = (key: string) => ["free", "pro", "special", unrecorded].indexOf(key);
  const modelRank = (key: string) => (key === unrecorded ? 1 : 0);
  return {
    days: dayList.map((day) => ({ day, ...(days.get(day) ?? empty()) })),
    totals,
    plans: {
      series: ordered(plans, planRank),
      days: dayList.map((day) => ({ day, values: planDays.get(day) ?? {} })),
      totals: planTotals,
    },
    models: {
      series: ordered(models, modelRank),
      days: dayList.map((day) => ({ day, values: modelDays.get(day) ?? {} })),
      totals: modelTotals,
    },
    versions: [...versions]
      .map(([version, amount]) => ({ version, amount }))
      .toSorted((a, b) => (b.version ?? 0) - (a.version ?? 0)),
    unpricedModels: [...unpriced].toSorted(),
    unrecordedModel: freeModel,
  };
}
