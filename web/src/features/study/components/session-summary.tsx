import Link from "next/link";

import { Mascot } from "@/components/brand";

import type { SessionSummary as Summary } from "../session";

/** A day, in milliseconds. */
const day = 86_400_000;

/** When [next] is, told by calendar day from now in the browser's time zone, as the phone does. */
function nextReviewSentence(next: number): string {
  const midnight = (time: number) => {
    const date = new Date(time);
    return new Date(date.getFullYear(), date.getMonth(), date.getDate()).getTime();
  };
  // Rounded, since a day across a daylight-saving change is an hour longer or shorter.
  const days = Math.round((midnight(next) - midnight(Date.now())) / day);
  const when = days <= 0 ? "오늘이에요" : days === 1 ? "내일이에요" : `${String(days)}일 뒤예요`;
  return `다음 복습은 ${when}. 잊을 때쯤 다시 보여 드릴게요.`;
}

/**
 * What a finished session shows in place of the current card: the mascot, the session's
 * counts, when its first card is due again once [nextReview] is known, its time, and the way
 * back.
 */
export function SessionSummary({
  summary,
  total,
  nextReview,
}: {
  summary: Summary;
  total: number;
  nextReview: number | null;
}) {
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
        <Mascot className="size-mascot-medium bg-brand-tint" />
        <h2 id="session-summary-title" className="text-title">
          오늘 할 카드를 마쳤어요
        </h2>
        {total === 0 ? (
          <p className="text-secondary text-muted">지금 학습할 카드가 없어요.</p>
        ) : (
          nextReview !== null && (
            <p className="text-secondary text-muted">{nextReviewSentence(nextReview)}</p>
          )
        )}
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
          <span className="text-body-strong">
            {Math.floor(seconds / 60)}분 {seconds % 60}초
          </span>
        </p>
      </div>
      <Link
        href="/"
        className="flex min-h-cta items-center justify-center rounded-button bg-ink px-6 text-label text-on-primary focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-ink"
      >
        덱으로 돌아가기
      </Link>
    </section>
  );
}
