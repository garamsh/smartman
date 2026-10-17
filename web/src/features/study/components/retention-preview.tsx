import Link from "next/link";

import { calendarDate, type RecordDay, retentionOver, share, targetRetention } from "../stats";

/** A share as whole percent. */
function percent(value: number): number {
  return Math.round(value * 100);
}

/** The sparkline's height, and its scale's floor at most. */
const height = 64;
const scaleFloor = 0.8;

/**
 * The 오늘 page's retention card, as the WebToday artboard draws it: the share of the last 30
 * study days' scheduled reviews answered "안다" against the 90% target, the gap, a line of each
 * day read as one label, and a link to the 기록 page; or a sentence when they hold no review.
 */
export function RetentionPreview({ days, timeZone }: { days: RecordDay[]; timeZone: string }) {
  const total = retentionOver(days);
  const target = percent(targetRetention);
  const link = (
    <Link
      href="/record"
      className="self-start text-label text-ink underline-offset-4 hover:underline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-ink"
    >
      기록에서 자세히 보기
    </Link>
  );
  if (!total) {
    return (
      <section
        aria-labelledby="retention-title"
        className="flex flex-col gap-3 rounded-previous bg-surface p-5"
      >
        <h2 id="retention-title" className="text-body-strong">
          기억률
        </h2>
        <p className="text-secondary text-ink-2">최근 30일 동안 복습한 카드가 없어요.</p>
        {link}
      </section>
    );
  }
  const value = percent(share(total));
  const gap = value - target;
  const lowest = Math.min(...days.map((day) => share(day)));
  const floor = Math.min(scaleFloor, Math.floor(lowest * 10) / 10);
  const y = (v: number) => ((1 - v) / (1 - floor)) * height;
  const first = days[0]?.dayStart ?? 0;
  const last = days[days.length - 1]?.dayStart ?? first;
  const x = (start: number) => (last === first ? 100 : ((start - first) / (last - first)) * 100);
  const line = days.map((day) => `${String(x(day.dayStart))},${String(y(share(day)))}`).join(" ");
  const date = (start: number) =>
    new Intl.DateTimeFormat("ko-KR", { month: "long", day: "numeric", timeZone: "UTC" }).format(
      calendarDate(start, timeZone),
    );
  return (
    <section
      aria-labelledby="retention-title"
      className="flex flex-col gap-3 rounded-previous bg-surface p-5"
    >
      <h2 id="retention-title" className="text-body-strong">
        기억률
      </h2>
      <div className="flex flex-wrap items-baseline gap-x-3 gap-y-1">
        <p className="text-figure text-ink">{value}%</p>
        <p className="text-caption text-ink-2">목표 {target}%</p>
        <p
          className={`rounded-full px-2 py-1 text-micro font-bold text-ink ${gap < 0 ? "bg-tint-amber" : "bg-brand-tint"}`}
        >
          {gap < 0
            ? `목표보다 ${String(-gap)}%p 낮아요`
            : gap > 0
              ? `목표보다 ${String(gap)}%p 높아요`
              : "목표만큼 맞혔어요"}
        </p>
      </div>
      <svg
        role="img"
        aria-label={`최근 30일 복습에서 맞힌 비율, 목표 ${String(target)}%: ${days.map((day) => `${date(day.dayStart)} ${String(percent(share(day)))}%`).join(", ")}`}
        viewBox={`0 0 100 ${String(height)}`}
        preserveAspectRatio="none"
        className="h-16 w-full overflow-visible"
      >
        <line
          x1="0"
          x2="100"
          y1={y(targetRetention)}
          y2={y(targetRetention)}
          className="stroke-know"
          strokeWidth="1.5"
          strokeDasharray="5 5"
          vectorEffect="non-scaling-stroke"
        />
        <polyline
          points={
            days.length > 1 ? line : `0,${String(y(share(total)))} 100,${String(y(share(total)))}`
          }
          fill="none"
          className="stroke-ink"
          strokeWidth="2.5"
          strokeLinejoin="round"
          strokeLinecap="round"
          vectorEffect="non-scaling-stroke"
        />
      </svg>
      {link}
    </section>
  );
}
