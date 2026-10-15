"use client";

import { useEffect, useRef } from "react";

import { describeContent } from "@/lib/card-content";

import type { PreviousAnswer } from "../session";

const answerNames = { know: "안다", dontKnow: "모른다" } as const;

/** Older answers fade a step per answer of depth, down to the last step. */
const depthClasses = ["", "opacity-85", "opacity-70", "opacity-55"] as const;

/**
 * Every answer of the session, oldest first and the newest nearest the current card, each a
 * button that toggles it. The list keeps the newest in view as answers arrive.
 */
export function PreviousAnswers({
  answers,
  onToggle,
}: {
  answers: PreviousAnswer[];
  onToggle: (position: number) => void;
}) {
  const list = useRef<HTMLElement>(null);
  useEffect(() => {
    if (list.current) list.current.scrollTop = list.current.scrollHeight;
  }, [answers.length]);

  if (answers.length === 0) return null;
  return (
    <section ref={list} aria-label="이전 답" className="max-h-72 overflow-y-auto">
      <p id="toggle-hint" className="sr-only">
        누르면 답이 바뀌어요.
      </p>
      <ol className="flex flex-col gap-2">
        {answers.map((answer, index) => {
          const depth = depthClasses[Math.min(answers.length - 1 - index, depthClasses.length - 1)];
          const front = describeContent(answer.card.front);
          const back = describeContent(answer.card.back);
          const name = answerNames[answer.answer];
          return (
            <li key={answer.position}>
              <button
                type="button"
                onClick={() => {
                  onToggle(answer.position);
                }}
                aria-label={`앞면: ${front}. 뒷면: ${back}. 답: ${name}${answer.changed ? ". 수정됨" : ""}`}
                aria-describedby="toggle-hint"
                title="눌러서 답 바꾸기"
                className={`grid min-h-13 w-full grid-cols-[1fr_1fr_auto] items-center gap-3 rounded-previous border border-hairline bg-surface px-4 py-2 text-left text-secondary focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-ink ${depth ?? ""}`}
              >
                <span className="line-clamp-2">{front}</span>
                <span className="line-clamp-2 text-ink-2">{back}</span>
                <span className="flex items-center gap-2">
                  {answer.changed && <span className="text-micro text-muted">수정됨</span>}
                  <span
                    aria-hidden
                    className={`size-2 rounded-full ${answer.answer === "know" ? "bg-know-dot" : "bg-dont-know"}`}
                  />
                </span>
              </button>
            </li>
          );
        })}
      </ol>
    </section>
  );
}
