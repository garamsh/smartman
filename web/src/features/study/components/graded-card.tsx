"use client";

import { Check, X } from "lucide-react";
import type { Ref } from "react";

import type { Answer } from "../answer-write";
import { useSwipe } from "../hooks/use-swipe";
import type { PreviousAnswer } from "../session";

/** Each grade's name, its fill and line, its chip, and its mark. */
export const grades = {
  know: {
    name: "안다",
    card: "border-know-line bg-know-card",
    line: "bg-know-line",
    chip: "bg-know text-on-know",
    Mark: Check,
  },
  dontKnow: {
    name: "모른다",
    card: "border-dont-know-line bg-dont-know-card",
    line: "bg-dont-know-line",
    chip: "bg-dont-know-text text-on-dont-know-text",
    Mark: X,
  },
} as const;

/** An answered card as the stack shows it: its card, its answer, and whether it was changed. */
type Graded = Pick<PreviousAnswer, "card" | "answer"> & { changed?: boolean };

/**
 * What a screen reader reads for an answered card: its sides, a whole card's front with its
 * blanks as "빈칸", and its grade.
 */
export function answerLabel(answer: Graded): string {
  const front = answer.card.whole?.spokenFront ?? answer.card.text.front;
  const changed = answer.changed ? ". 수정됨" : "";
  return `앞면: ${front}. 뒷면: ${answer.card.text.back}. 응답: ${grades[answer.answer].name}${changed}`;
}

/** A grade's chip: its mark and its word, so the grade never rests on colour alone. */
export function GradeChip({ answer, className = "" }: { answer: Answer; className?: string }) {
  const { name, chip, Mark } = grades[answer];
  return (
    <span
      aria-hidden
      className={`flex h-6 items-center gap-1 rounded-full px-2 text-micro font-bold ${chip} ${className}`}
    >
      <Mark className="size-3" strokeWidth={3} />
      {name}
    </span>
  );
}

/** The card's tilt, in radians, per pixel of swipe, as on the phone. */
export const tiltPerPixel = 0.0006;

/** Each answer's tint behind a card moved toward it, on the side the card leaves bare. */
export const answerTints = {
  know: "justify-start bg-tint-green text-on-know-tint",
  dontKnow: "justify-end bg-tint-red text-on-dont-know-tint",
} as const;

/** What a swipe toward an answer shows behind the previous card. */
const reveals = {
  know: { text: "안다로 바꿔요", tint: answerTints.know },
  dontKnow: { text: "모른다로 바꿔요", tint: answerTints.dontKnow },
} as const;

/**
 * The card answered just before the current one, with both sides shown at the current card's
 * sizes, or a whole card's front with its blanks filled, on its grade's fill inside its grade's
 * line, and its grade's chip on its top edge. A click opens the whole card. A horizontal touch
 * swipe ([useSwipe]) follows the finger, shows the answer it would give behind it, and toward
 * the other answer changes to it; a vertical one scrolls the page. Without [onRedecide] it is
 * not changed from here, and [label] names it above its sides.
 */
export function GradedCard({
  answer,
  onRedecide,
  onOpen,
  openRef,
  label,
}: {
  answer: Graded;
  onRedecide?: (answer: Answer) => void;
  onOpen: () => void;
  openRef?: Ref<HTMLButtonElement>;
  label?: string;
}) {
  const grade = grades[answer.answer];
  const { offset, dragging, toward, handlers, endsSwipe } = useSwipe({
    held: answer.answer,
    onCommit: onRedecide,
  });
  const reveal = toward !== null && toward !== answer.answer ? reveals[toward] : null;

  return (
    <article
      aria-label={label ? `${label}. ${answerLabel(answer)}` : answerLabel(answer)}
      {...handlers}
      className="relative flex w-full touch-pan-y"
    >
      {reveal && (
        <div
          aria-hidden
          className={`absolute inset-0 flex items-center rounded-previous px-5 text-secondary font-bold ${reveal.tint}`}
        >
          {reveal.text}
        </div>
      )}
      <button
        ref={openRef}
        type="button"
        aria-label="카드 전체 보기"
        aria-haspopup="dialog"
        onClick={() => {
          if (endsSwipe()) return;
          onOpen();
        }}
        style={{
          transform: `translateX(${String(offset)}px) rotate(${String(offset * tiltPerPixel)}rad)`,
        }}
        className={`pressable relative grid w-full grid-cols-[1fr_auto_1fr] rounded-previous border-[1.5px] text-center focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-ink ${grade.card} ${dragging ? "" : "motion-safe:transition-transform motion-safe:duration-300"}`}
      >
        <GradeChip answer={answer.answer} className="absolute -top-3 right-4" />
        {label && (
          <span aria-hidden className="absolute top-3 left-4 text-micro text-muted">
            {label}
          </span>
        )}
        {answer.card.whole ? (
          <span className="col-span-3 flex items-center justify-center p-4 text-back text-ink lg:p-6">
            {answer.card.whole.filled}
          </span>
        ) : (
          <>
            <span className="flex items-center justify-center p-4 text-front text-ink lg:p-6">
              <span className="line-clamp-6 break-words">
                {answer.card.sides?.front ?? answer.card.text.front}
              </span>
            </span>
            <span aria-hidden className={`my-7 w-px ${grade.line}`} />
            <span className="flex items-center justify-center p-4 text-back text-ink-2 lg:p-6">
              <span className="line-clamp-6 break-words">
                {answer.card.sides?.back ?? answer.card.text.back}
              </span>
            </span>
          </>
        )}
      </button>
    </article>
  );
}
