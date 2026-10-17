import { ArrowUp, Eye, MoveHorizontal } from "lucide-react";

import type { SessionSize } from "../session";

/** The three lines on how to study, each after its icon; the web's answer line names its keys. */
const lines = [
  { Icon: Eye, text: "카드를 누르면 답이 보여요" },
  { Icon: MoveHorizontal, text: "알면 안다(→), 모르면 모른다(←)를 눌러요" },
  { Icon: ArrowUp, text: "답한 카드는 여기로 올라와요. 밀어서 바꿀 수 있어요" },
] as const;

/**
 * In the previous card's place from a session's start until its first answer: a panel with a
 * dashed outline and no fill, so it never reads as a card, holding the session's [size] and three
 * lines on how to study.
 */
export function SessionGuide({ size }: { size: SessionSize }) {
  return (
    <section
      aria-label="학습 안내"
      className="flex w-full flex-col justify-center gap-3 rounded-previous border-[1.5px] border-dashed border-outline px-5 py-4"
    >
      <p className="text-body font-bold text-ink">
        오늘 {size.cards}장 · 약 {size.minutes}분
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
