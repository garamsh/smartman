"use client";

import { Flame } from "lucide-react";
import Link from "next/link";
import { useEffect, useRef } from "react";

import { Mascot } from "@/components/brand";

import type { Completion } from "../session";

/**
 * The completion card in the current card's place once no card is left today: the mascot, the
 * heading, today's answers, time and streak, and the choice to go on as practice or to stop.
 * It takes the focus when it appears, so a keyboard reaches its choice at once.
 */
export function CompletionCard({
  completion,
  onPractice,
}: {
  completion: Completion;
  onPractice: () => void;
}) {
  const keepStudying = useRef<HTMLButtonElement>(null);
  useEffect(() => {
    keepStudying.current?.focus();
  }, []);
  const minutes = Math.ceil(completion.timeSpentMs / 60_000);
  return (
    <section
      aria-labelledby="completion-title"
      className="flex flex-col items-center gap-3 rounded-card bg-surface px-5 pt-7 pb-5 text-center shadow-raised"
    >
      <Mascot className="size-mascot-medium bg-brand-tint" />
      <h2 id="completion-title" className="text-title">
        오늘 학습 완료
      </h2>
      <p className="flex flex-wrap items-center justify-center gap-x-4 gap-y-1 text-secondary text-ink-2">
        <span>
          <b className="text-know">{completion.knowCount}</b> 안다
        </span>
        <span>
          <b className="text-dont-know-text">{completion.dontKnowCount}</b> 모른다
        </span>
        <b className="text-ink">{minutes}분</b>
        <span className="flex items-center gap-1">
          <Flame aria-hidden className="size-small-icon text-ink-2" strokeWidth={2} />
          <span className="sr-only">연속 </span>
          <b className="text-ink">{completion.streak}일</b>
        </span>
      </p>
      <div className="mt-1 flex w-full flex-col gap-1">
        <button
          ref={keepStudying}
          type="button"
          onClick={onPractice}
          className="flex min-h-cta items-center justify-center rounded-button bg-ink px-6 text-label text-on-primary focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-ink"
        >
          계속 학습
        </button>
        <Link
          href="/"
          className="flex min-h-button items-center justify-center rounded-button px-6 text-label text-ink-2 focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-ink"
        >
          그만하기
        </Link>
      </div>
    </section>
  );
}
