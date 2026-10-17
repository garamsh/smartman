import { ArrowUp, MoveHorizontal } from "lucide-react";

import type { SessionSize } from "../session";

/** The two lines on how to study, each after its icon; the web's answer line names its keys. */
const lines = [
  { Icon: MoveHorizontal, text: "알면 안다(→), 모르면 모른다(←)를 눌러요" },
  { Icon: ArrowUp, text: "답한 카드는 뜻과 함께 여기로 올라와요. 밀어서 바꿀 수 있어요" },
] as const;

/**
 * In the previous card's place from a session's start until its first answer: a panel with a
 * dashed outline and no fill, so it never reads as a card, holding the session's [size], or that
 * today's cards are done where it holds none, and two lines on how to study.
 */
export function SessionGuide({ size }: { size: SessionSize }) {
  return (
    <section
      aria-label="학습 안내"
      className="flex w-full flex-col justify-center gap-3 rounded-previous border-[1.5px] border-dashed border-outline px-5 py-4"
    >
      <p className="text-body font-bold text-ink">
        {size.cards === 0
          ? "오늘 할 카드를 다 했어요"
          : `오늘 ${String(size.cards)}장 · 약 ${String(size.minutes)}분`}
      </p>
      <ul className="flex flex-col gap-3">
        {lines.map(({ Icon, text }) => (
          <li key={text} className="flex items-start gap-3 text-secondary text-ink-2">
            <Icon aria-hidden className="mt-0.5 size-small-icon shrink-0" strokeWidth={2} />
            {text}
          </li>
        ))}
      </ul>
    </section>
  );
}
