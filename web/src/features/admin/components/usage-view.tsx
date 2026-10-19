import Link from "next/link";

import type { Amount, Stack, Usage } from "../usage";
import { DailyUsageChart, StackedCostChart, usd } from "./usage-charts";

/** An amount in words: its photos and estimated cost, and the photos no measured cost prices. */
function amountWords({ photos, usd: cost, unpriced }: Amount): string {
  return `${String(photos)}장 · ${usd(cost)}${unpriced > 0 ? ` (비용 모르는 ${String(unpriced)}장 제외)` : ""}`;
}

const cell = "px-4 py-2 text-right";
const head = "px-4 py-2 text-right font-medium";

/** One table of named amounts, each row a series or version with its photos and cost. */
function AmountTable({
  label,
  rows,
}: {
  label: string;
  rows: { key: string; name: React.ReactNode; amount: Amount }[];
}) {
  return (
    <table aria-label={label} className="w-full rounded-card bg-surface text-secondary">
      <thead>
        <tr className="text-left text-muted">
          <th scope="col" className="px-4 py-2 font-medium">
            {label}
          </th>
          <th scope="col" className={head}>
            사진
          </th>
          <th scope="col" className={head}>
            예상 비용
          </th>
        </tr>
      </thead>
      <tbody>
        {rows.map(({ key, name, amount }) => (
          <tr key={key} className="border-t border-hairline">
            <th scope="row" className="px-4 py-2 text-left font-normal">
              {name}
            </th>
            <td className={cell}>{amount.photos}장</td>
            <td className={cell}>
              {usd(amount.usd)}
              {amount.unpriced > 0 && ` + 모름 ${String(amount.unpriced)}장`}
            </td>
          </tr>
        ))}
      </tbody>
    </table>
  );
}

/** A stack's series as table rows, and the sentence that names each series' 30-day cost. */
function stackRows(stack: Stack) {
  return stack.series.map((series) => ({
    key: series.key,
    name: series.label,
    amount: stack.totals[series.key] ?? { photos: 0, usd: 0, unpriced: 0 },
  }));
}

function stackSummary(title: string, stack: Stack): string {
  const parts = stackRows(stack).map(({ name, amount }) => `${name} ${usd(amount.usd)}`);
  return parts.length === 0
    ? `${title}: 최근 30일 사진이 없어요.`
    : `${title}, 최근 30일: ${parts.join(", ")}.`;
}

/**
 * The last 30 UTC days of photo extractions: today, 7 and 30 days' totals, each day's photos and
 * cost, the cost by plan and by model, and the photos by prompt version. Each chart is named by a
 * sentence and followed by a table of its values.
 */
export function UsageView({ usage }: { usage: Usage }) {
  const busiest = usage.days.reduce<(typeof usage.days)[number] | undefined>(
    (top, day) => (top === undefined || day.photos > top.photos ? day : top),
    undefined,
  );
  const dailySummary =
    usage.totals.month.photos === 0 || busiest === undefined
      ? "최근 30일 동안 사진 추출이 없어요."
      : `최근 30일 사진 ${amountWords(usage.totals.month)}. 가장 많은 날은 ${busiest.day}, ${String(busiest.photos)}장이에요.`;
  return (
    <section aria-label="사진 추출" className="flex flex-col gap-4">
      <h2 className="text-section">사진 추출</h2>
      <dl className="grid gap-row-gap lg:grid-cols-3">
        {(
          [
            ["오늘", usage.totals.today],
            ["최근 7일", usage.totals.week],
            ["최근 30일", usage.totals.month],
          ] as const
        ).map(([term, amount]) => (
          <div key={term} className="flex flex-col gap-1 rounded-card bg-surface p-5">
            <dt className="text-secondary text-muted">{term}</dt>
            <dd className="text-body-strong">{amountWords(amount)}</dd>
          </div>
        ))}
      </dl>
      <p className="text-caption text-muted">
        UTC 날짜 기준이에요. 예상 비용은 사진마다 그 사진을 만든 모델의 eval 측정 비용으로 계산해요.
        {usage.unrecordedModel === null
          ? ""
          : ` 기록 전 사진은 무료 요금제의 모델 ${usage.unrecordedModel}로 계산했어요.`}
        {usage.unpricedModels.length === 0
          ? ""
          : ` 측정하지 않은 모델(${usage.unpricedModels.join(", ")})의 사진은 비용에서 빠졌어요.`}
      </p>
      <figure className="flex flex-col gap-3">
        <figcaption className="text-label font-semibold">
          날짜별 사진(막대)과 예상 비용(점선)
        </figcaption>
        <DailyUsageChart days={usage.days} summary={dailySummary} />
        <table
          aria-label="날짜별 사진과 예상 비용"
          className="w-full rounded-card bg-surface text-secondary"
        >
          <thead>
            <tr className="text-left text-muted">
              <th scope="col" className="px-4 py-2 font-medium">
                날짜
              </th>
              <th scope="col" className={head}>
                사진
              </th>
              <th scope="col" className={head}>
                예상 비용
              </th>
            </tr>
          </thead>
          <tbody>
            {usage.days.toReversed().map((day) => (
              <tr key={day.day} className="border-t border-hairline">
                <th scope="row" className="px-4 py-2 text-left font-normal">
                  {day.day}
                </th>
                <td className={cell}>{day.photos}장</td>
                <td className={cell}>
                  {usd(day.usd)}
                  {day.unpriced > 0 && ` + 모름 ${String(day.unpriced)}장`}
                </td>
              </tr>
            ))}
          </tbody>
        </table>
      </figure>
      {(
        [
          ["요금제별 예상 비용", "요금제", usage.plans],
          ["모델별 예상 비용", "모델", usage.models],
        ] as const
      ).map(([title, column, stack]) => (
        <figure key={title} className="flex flex-col gap-3">
          <figcaption className="text-label font-semibold">{title}</figcaption>
          <StackedCostChart stack={stack} summary={stackSummary(title, stack)} />
          <AmountTable label={column} rows={stackRows(stack)} />
        </figure>
      ))}
      <section aria-label="프롬프트 버전별" className="flex flex-col gap-3">
        <h3 className="text-label font-semibold">프롬프트 버전별</h3>
        <AmountTable
          label="버전"
          rows={usage.versions.map(({ version, amount }) => ({
            key: String(version),
            name:
              version === null ? (
                "기록 전"
              ) : (
                <Link
                  href={`/admin/prompts/${String(version)}`}
                  className="underline underline-offset-4 focus-visible:outline-2 focus-visible:outline-ink"
                >
                  버전 {version}
                </Link>
              ),
            amount,
          }))}
        />
      </section>
    </section>
  );
}
