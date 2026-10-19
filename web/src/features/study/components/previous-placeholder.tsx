import { ArrowUp } from "lucide-react";

/**
 * The previous card's place while it holds no card: a dashed outline with no fill, so it never
 * reads as a card, around an up arrow and a line saying that answered cards stack here.
 */
export function PreviousPlaceholder() {
  return (
    <section
      aria-label="응답한 카드가 여기에 쌓여요"
      className="flex w-full flex-col items-center justify-center gap-2 rounded-previous border-[1.5px] border-dashed border-outline px-5 py-4 text-muted"
    >
      <ArrowUp aria-hidden className="size-7" strokeWidth={1.8} />
      <p aria-hidden className="text-secondary">
        응답한 카드가 여기에 쌓여요
      </p>
    </section>
  );
}
