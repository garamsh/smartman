import { Play } from "lucide-react";
import Image from "next/image";
import Link from "next/link";

/**
 * The home page's today card, on the brand's navy: what a session over every deck would study
 * now, split into due and new, about how many [minutes] it takes, whether new cards pause for a
 * [backlog] of reviews, and its button, with the symbol faint in the corner; with none, that
 * today's cards are done.
 */
export function TodayHeader({
  decks,
  review,
  fresh,
  backlog,
  minutes,
}: {
  decks: readonly string[];
  review: number;
  fresh: number;
  backlog: boolean;
  minutes: number;
}) {
  const total = review + fresh;
  return (
    <section
      aria-labelledby="today-title"
      className="relative flex flex-col gap-5 overflow-hidden rounded-card bg-hero p-6 text-on-hero shadow-card"
    >
      <span aria-hidden className="absolute -top-4 -right-4 size-hero-symbol opacity-12">
        {/* The white symbol in both themes, on the navy card. */}
        <Image
          src="/brand/smartman-symbol-dark.svg"
          alt=""
          width={200}
          height={200}
          unoptimized
          className="size-full"
        />
      </span>
      {total === 0 ? (
        <h2 id="today-title" className="text-title">
          오늘 할 카드를 다 했어요
        </h2>
      ) : (
        <>
          <div className="flex flex-col gap-1">
            <p className="text-section">오늘 할 카드</p>
            <h2 id="today-title" aria-label={`오늘 할 카드 ${String(total)}장`}>
              <span className="text-figure">{total}</span> <span className="text-headline">장</span>
            </h2>
            <p className="text-secondary">
              복습 {review} · 새 카드 {fresh} · 약 {minutes}분
            </p>
            {backlog && <p className="text-secondary">밀린 복습을 마칠 때까지 새 카드는 쉬어요.</p>}
          </div>
          <Link
            href={`/study?decks=${decks.map(encodeURIComponent).join(",")}`}
            className="flex min-h-button items-center justify-center gap-2 rounded-button bg-on-hero px-6 text-label text-brand focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-on-hero"
          >
            <Play aria-hidden className="size-small-icon" strokeWidth={2} />
            모두 학습
          </Link>
        </>
      )}
    </section>
  );
}
