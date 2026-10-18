import { spoken } from "@/features/decks";

import type { PreviousAnswer } from "../session";
import { answerLabel, GradeChip } from "./graded-card";

/**
 * Beside the cards on a wide screen: this session's answers, oldest first, with the count of
 * each, every one a button that changes it to the other answer.
 */
export function AnswerList({
  answers,
  onToggle,
}: {
  answers: PreviousAnswer[];
  onToggle: (position: number) => void;
}) {
  const know = answers.filter(({ answer }) => answer === "know").length;
  return (
    <aside
      aria-label="이번 학습"
      className="hidden w-full max-w-85 shrink-0 flex-col gap-2 self-start rounded-card bg-surface p-4 lg:flex"
    >
      <div className="mb-1 flex items-baseline justify-between">
        <h2 className="text-label">이번 학습</h2>
        <span className="text-caption text-ink-2">
          안다 {know} · 모른다 {answers.length - know}
        </span>
      </div>
      <p id="toggle-hint" className="sr-only">
        누르면 답이 바뀌어요.
      </p>
      <ol className="flex flex-col gap-1">
        {answers.map((answer) => (
          <li key={answer.position}>
            <button
              type="button"
              onClick={() => {
                onToggle(answer.position);
              }}
              aria-label={answerLabel(answer)}
              aria-describedby="toggle-hint"
              title="눌러서 답 바꾸기"
              className="flex min-h-tap-target w-full items-center gap-3 rounded-field px-3 text-left hover:bg-ground focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-ink"
            >
              <span className="flex-1 truncate text-secondary font-bold">
                {spoken(answer.card.text.front, true)}
              </span>
              <GradeChip answer={answer.answer} />
            </button>
          </li>
        ))}
      </ol>
    </aside>
  );
}
