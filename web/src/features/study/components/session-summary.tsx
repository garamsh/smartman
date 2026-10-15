import Link from "next/link";

import type { SessionSummary as Summary } from "../session";

/** What a finished session shows in place of the current card. */
export function SessionSummary({ summary, total }: { summary: Summary; total: number }) {
  const seconds = Math.floor(summary.timeSpentMs / 1000);
  return (
    <section
      aria-labelledby="session-summary-title"
      className="flex flex-col gap-4 rounded-card bg-surface p-6"
    >
      <h2 id="session-summary-title" className="text-2xl font-bold">
        {total === 0 ? "지금 학습할 카드가 없습니다." : "학습 끝"}
      </h2>
      {total > 0 && (
        <ul className="flex flex-col gap-1 text-muted">
          <li>학습한 카드: {summary.cardsStudied}장</li>
          <li>안다: {summary.knowCount}번</li>
          <li>모른다: {summary.dontKnowCount}번</li>
          <li>
            걸린 시간: {Math.floor(seconds / 60)}분 {seconds % 60}초
          </li>
        </ul>
      )}
      <Link
        href="/"
        className="flex min-h-13 items-center justify-center rounded-row bg-ink px-6 font-semibold text-surface focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-ink"
      >
        완료
      </Link>
    </section>
  );
}
