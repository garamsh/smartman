"use client";

import { useEffect, useRef } from "react";

import { isWholeCard, WholeCard } from "@/features/decks";

import type { PreviousAnswer } from "../session";
import { CardSide } from "./card-side";
import { GradeChip, grades } from "./graded-card";

/**
 * The whole of a card answered earlier, front and back, or a whole card's front with its blanks
 * filled, over the screen until it is closed.
 */
export function CardDetail({
  answer,
  onClose,
}: {
  answer: Pick<PreviousAnswer, "card" | "answer">;
  onClose: () => void;
}) {
  const close = useRef<HTMLButtonElement>(null);
  useEffect(() => {
    close.current?.focus();
  }, []);

  return (
    <div className="fixed inset-0 flex items-center justify-center bg-shadow/40 px-4">
      <div
        role="dialog"
        aria-modal="true"
        aria-labelledby="card-detail-title"
        className="flex max-h-[90dvh] w-full max-w-study flex-col gap-4 overflow-y-auto rounded-card bg-surface p-6"
      >
        <div className="flex items-center justify-between gap-4">
          <h2 id="card-detail-title" className="text-headline text-ink">
            카드
          </h2>
          <GradeChip answer={answer.answer} />
          <span className="sr-only">답: {grades[answer.answer].name}</span>
        </div>
        {isWholeCard(answer.card.front) ? (
          <WholeCard blocks={answer.card.front} revealed className="text-answer" />
        ) : (
          <>
            <section aria-labelledby="card-detail-front" className="flex flex-col gap-2">
              <h3 id="card-detail-front" className="text-section text-muted">
                앞면
              </h3>
              <CardSide blocks={answer.card.front} size="question" />
            </section>
            <section aria-labelledby="card-detail-back" className="flex flex-col gap-2">
              <h3 id="card-detail-back" className="text-section text-muted">
                뒷면
              </h3>
              <CardSide blocks={answer.card.back} size="answer" />
            </section>
          </>
        )}
        <button
          ref={close}
          type="button"
          onClick={onClose}
          aria-keyshortcuts="Escape"
          className="min-h-button rounded-row bg-ink px-6 font-semibold text-surface focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-ink"
        >
          닫기
        </button>
      </div>
    </div>
  );
}
