import Link from "next/link";

import { Mascot } from "@/components/brand";

import type { SessionSummary as Summary } from "../session";

/**
 * What a finished session shows in place of the current card: the mascot, the session's
 * counts, its time, and the way back.
 */
export function SessionSummary({ summary, total }: { summary: Summary; total: number }) {
  const seconds = Math.floor(summary.timeSpentMs / 1000);
  const tiles = [
    { label: "학습한 카드", count: summary.cardsStudied, tone: "text-ink" },
    { label: "안다", count: summary.knowCount, tone: "text-know" },
    { label: "모른다", count: summary.dontKnowCount, tone: "text-dont-know-text" },
  ];
  return (
    <section
      aria-labelledby="session-summary-title"
      className="flex flex-col gap-6 rounded-card bg-surface p-6 shadow-raised"
    >
      <div className="flex flex-col items-center gap-4 text-center">
        <Mascot className="size-28 bg-brand-tint" />
        <h2 id="session-summary-title" className="text-title">
          오늘 할 카드를 마쳤어요
        </h2>
        {total === 0 && <p className="text-secondary text-muted">지금 학습할 카드가 없어요.</p>}
      </div>
      <div className="flex flex-col gap-2">
        <ul aria-label="결과" className="grid grid-cols-3 gap-2">
          {tiles.map(({ label, count, tone }) => (
            <li
              key={label}
              className="flex flex-col items-center gap-1 rounded-row bg-ground px-2 py-4"
            >
              <span className={`text-title ${tone}`}>{count}</span>
              <span className="text-caption text-muted">{label}</span>
            </li>
          ))}
        </ul>
        <p className="flex items-center justify-between rounded-row bg-ground p-4">
          <span className="text-secondary text-muted">걸린 시간</span>
          <span className="text-body font-bold">
            {Math.floor(seconds / 60)}분 {seconds % 60}초
          </span>
        </p>
      </div>
      <Link
        href="/"
        className="flex min-h-14 items-center justify-center rounded-button bg-ink px-6 text-label text-on-primary focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-ink"
      >
        덱으로 돌아가기
      </Link>
    </section>
  );
}
