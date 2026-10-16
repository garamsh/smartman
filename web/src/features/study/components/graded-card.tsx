import { Check, X } from "lucide-react";

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

/** What a screen reader reads for an answer of the session: its sides and its grade. */
export function answerLabel(answer: PreviousAnswer): string {
  const { front, back } = answer.card.text;
  const changed = answer.changed ? ". 수정됨" : "";
  return `앞면: ${front}. 뒷면: ${back}. 답: ${grades[answer.answer].name}${changed}`;
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

/** How a previous card stands: above the current card at rest, centred, or beside the centre. */
export type Standing = "rest" | "centred" | "side";

const standings: Record<Standing, string> = {
  rest: "scale-94",
  centred: "scale-100 shadow-raised",
  side: "scale-90 opacity-70",
};

/**
 * A card answered earlier, with both sides shown, on its grade's fill inside its grade's line,
 * and its grade's chip on its top edge. Centred, it offers the change to the other answer, with
 * the key that makes it.
 */
export function GradedCard({
  answer,
  standing,
  onRedecide,
}: {
  answer: PreviousAnswer;
  standing: Standing;
  onRedecide: (answer: Answer) => void;
}) {
  const grade = grades[answer.answer];
  const other: Answer = answer.answer === "know" ? "dontKnow" : "know";
  return (
    <article
      aria-label={answerLabel(answer)}
      className={`relative w-full max-w-study rounded-previous border-[1.5px] motion-safe:transition-[transform,opacity] motion-safe:duration-300 ${grade.card} ${standings[standing]}`}
    >
      <GradeChip answer={answer.answer} className="absolute -top-3 right-4" />
      <div className="grid min-h-28 grid-cols-[1fr_auto_1fr]">
        <p className="flex items-center justify-center p-4 text-center text-headline text-ink">
          <span className="line-clamp-2 break-words">{answer.card.text.front}</span>
        </p>
        <span aria-hidden className={`my-5 w-px ${grade.line}`} />
        <p className="flex items-center justify-center p-4 text-center text-body text-ink-2">
          <span className="line-clamp-2 break-words">{answer.card.text.back}</span>
        </p>
      </div>
      {standing === "centred" && (
        <button
          type="button"
          onClick={() => {
            onRedecide(other);
          }}
          aria-keyshortcuts={other === "know" ? "ArrowRight" : "ArrowLeft"}
          className={`mx-4 mb-4 flex min-h-tap-target w-[calc(100%-2rem)] items-center justify-center gap-2 rounded-button text-label focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-ink ${
            other === "know"
              ? "bg-tint-green text-on-know-tint"
              : "bg-tint-red text-on-dont-know-tint"
          }`}
        >
          {other === "know" ? "안다로 바꾸기" : "모른다로 바꾸기"}
          <kbd aria-hidden className="font-sans text-caption font-normal">
            {other === "know" ? "→" : "←"}
          </kbd>
        </button>
      )}
    </article>
  );
}
