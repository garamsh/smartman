import { Eye, MoveHorizontal } from "lucide-react";

import { Mascot } from "@/design/brand";

/** The two lines on how to study, each after its icon. */
const lines = [
  { Icon: Eye, text: "먼저 떠올려 보고, 카드를 눌러 답을 확인해요" },
  { Icon: MoveHorizontal, text: "알면 오른쪽, 모르면 왼쪽을 눌러요" },
] as const;

/**
 * In the previous card's place before the first answer of the user's first session: the mascot
 * and two lines on how to study, show the answer and answer.
 */
export function FirstRunGuide() {
  return (
    <section aria-label="학습 안내" className="flex w-full max-w-study flex-col items-center gap-3">
      <Mascot className="size-mascot-guide" />
      <ul className="flex w-full flex-col gap-3">
        {lines.map(({ Icon, text }) => (
          <li
            key={text}
            className="flex items-center gap-3 rounded-button bg-surface px-4 py-3 text-secondary text-ink-2"
          >
            <span className="flex size-8 shrink-0 items-center justify-center rounded-field bg-brand-tint text-ink">
              <Icon aria-hidden className="size-small-icon" strokeWidth={2} />
            </span>
            {text}
          </li>
        ))}
      </ul>
    </section>
  );
}
