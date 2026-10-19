"use client";

import { Check, X } from "lucide-react";
import { type PointerEvent, type Ref, useRef, useState } from "react";

import type { Answer } from "../answer-write";
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
  const front = answer.card.whole?.question ?? answer.card.text.front;
  const changed = answer.changed ? ". 수정됨" : "";
  return `앞면: ${front}. 뒷면: ${answer.card.text.back}. 답: ${grades[answer.answer].name}${changed}`;
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

/** The swipe past which a release changes the answer, in pixels, as on the phone. */
export const commitDistance = 100;

/** The release speed, in pixels per millisecond, that changes it whatever the distance. */
export const commitVelocity = 0.7;

/** How long, in milliseconds, a swipe's last movement counts toward a fling. */
const flingWindow = 100;

/** How far the card follows a swipe toward the answer it already has. */
const sameAnswerResistance = 0.25;

/** The card's tilt, in radians, per pixel of swipe, as on the phone. */
const tiltPerPixel = 0.0006;

/** How far a touch moves before it is read as a swipe or as a scroll. */
const slop = 8;

/** What a swipe toward an answer shows behind the card, and the side it shows on. */
const reveals = {
  know: { text: "안다로 바꿔요", tint: "justify-start bg-tint-green text-on-know-tint" },
  dontKnow: { text: "모른다로 바꿔요", tint: "justify-end bg-tint-red text-on-dont-know-tint" },
} as const;

/** A touch under way: where it started, its latest point and time in milliseconds, its speed. */
type Touch = {
  id: number;
  x: number;
  y: number;
  lastX: number;
  lastAt: number;
  velocity: number;
  swiping: boolean;
};

/**
 * The card answered just before the current one, with both sides shown at the current card's
 * sizes, or a whole card's front with its blanks filled, on its grade's fill inside its grade's
 * line, and its grade's chip on its top edge. A click opens the whole card. A horizontal touch swipe follows the finger, shows the answer it
 * would give behind it, and released past [commitDistance], or flung, toward the other answer
 * changes to it; a vertical one scrolls the page. Without [onRedecide] it is not changed from
 * here, and [label] names it above its sides.
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
  const [offset, setOffset] = useState(0);
  const [dragging, setDragging] = useState(false);
  const touch = useRef<Touch | null>(null);
  /** Whether the click that ends a swipe is to be ignored. */
  const swiped = useRef(false);

  const target: Answer = offset > 0 ? "know" : "dontKnow";
  const reveal = offset !== 0 && target !== answer.answer ? reveals[target] : null;

  function onPointerDown(event: PointerEvent) {
    if (event.pointerType !== "touch" || !onRedecide) return;
    touch.current = {
      id: event.pointerId,
      x: event.clientX,
      y: event.clientY,
      lastX: event.clientX,
      lastAt: Date.now(),
      velocity: 0,
      swiping: false,
    };
  }
  function onPointerMove(event: PointerEvent) {
    const at = touch.current;
    if (at?.id !== event.pointerId) return;
    const dx = event.clientX - at.x;
    if (!at.swiping) {
      // Mostly vertical: a scroll, which the page keeps (touch-action: pan-y).
      if (Math.abs(event.clientY - at.y) > slop && Math.abs(event.clientY - at.y) > Math.abs(dx)) {
        touch.current = null;
        return;
      }
      if (Math.abs(dx) <= slop) return;
      at.swiping = true;
      setDragging(true);
    }
    const now = Date.now();
    const elapsed = now - at.lastAt;
    if (elapsed > 0) at.velocity = (event.clientX - at.lastX) / elapsed;
    at.lastX = event.clientX;
    at.lastAt = now;
    const toward: Answer = dx > 0 ? "know" : "dontKnow";
    setOffset(toward === answer.answer ? dx * sameAnswerResistance : dx);
  }
  function onPointerEnd(event: PointerEvent, cancelled: boolean) {
    const at = touch.current;
    if (at?.id !== event.pointerId) return;
    touch.current = null;
    if (!at.swiping) return;
    swiped.current = true;
    const dx = event.clientX - at.x;
    const toward: Answer = dx > 0 ? "know" : "dontKnow";
    // A finger held still before it lifts flings nothing.
    const velocity = Date.now() - at.lastAt > flingWindow ? 0 : at.velocity;
    const committed =
      !cancelled &&
      toward !== answer.answer &&
      (Math.abs(dx) >= commitDistance ||
        (Math.abs(velocity) >= commitVelocity && Math.sign(velocity) === Math.sign(dx)));
    setDragging(false);
    setOffset(0);
    if (committed) onRedecide?.(toward);
  }

  return (
    <article
      aria-label={label ? `${label}. ${answerLabel(answer)}` : answerLabel(answer)}
      onPointerDown={onPointerDown}
      onPointerMove={onPointerMove}
      onPointerUp={(event) => {
        onPointerEnd(event, false);
      }}
      onPointerCancel={(event) => {
        onPointerEnd(event, true);
      }}
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
          if (swiped.current) {
            swiped.current = false;
            return;
          }
          onOpen();
        }}
        style={{
          transform: `translateX(${String(offset)}px) rotate(${String(offset * tiltPerPixel)}rad)`,
        }}
        className={`relative grid w-full grid-cols-[1fr_auto_1fr] rounded-previous border-[1.5px] text-center focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-ink ${grade.card} ${dragging ? "" : "motion-safe:transition-transform motion-safe:duration-300"}`}
      >
        <GradeChip answer={answer.answer} className="absolute -top-3 right-4" />
        {label && (
          <span aria-hidden className="absolute top-3 left-4 text-micro text-muted">
            {label}
          </span>
        )}
        {answer.card.whole ? (
          <span className="col-span-3 flex items-center justify-center p-4 text-answer text-ink lg:p-6">
            {answer.card.whole.filled}
          </span>
        ) : (
          <>
            <span className="flex items-center justify-center p-4 text-question text-ink lg:p-6">
              <span className="line-clamp-6 break-words">
                {answer.card.sides?.front ?? answer.card.text.front}
              </span>
            </span>
            <span aria-hidden className={`my-7 w-px ${grade.line}`} />
            <span className="flex items-center justify-center p-4 text-answer text-ink-2 lg:p-6">
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
