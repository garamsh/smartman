import type { DeckState } from "../read-admin";

/** A deck's state in words: deleted, or public or private, and hidden. */
export function deckStateWords(state: DeckState): string[] {
  if (state.deleted) return ["삭제됨"];
  return [state.visibility === "public" ? "공개" : "비공개", ...(state.hidden ? ["숨김"] : [])];
}

/** A deck's state as chips. */
export function DeckStateChips({ state }: { state: DeckState }) {
  return (
    <span className="flex flex-wrap gap-1">
      {deckStateWords(state).map((word) => (
        <span
          key={word}
          className={`rounded-full px-2 py-0.5 text-micro font-semibold ${
            word === "숨김" ? "bg-tint-red text-dont-know-text" : "bg-ground text-ink-2"
          }`}
        >
          {word}
        </span>
      ))}
    </span>
  );
}
