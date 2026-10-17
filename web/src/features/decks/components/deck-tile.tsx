import { deckTint } from "../deck-tint";
import type { Deck } from "../library";

/** A deck's initial on the tile tinted as the app tints it, hidden from screen readers. */
export function DeckTile({
  deck,
  size = "size-deck-tile text-headline",
}: {
  deck: Deck;
  size?: string;
}) {
  return (
    <span
      aria-hidden
      className={`flex shrink-0 items-center justify-center rounded-field font-extrabold ${size} ${deckTint(deck.id)}`}
    >
      {deck.name.trim().charAt(0).toLocaleUpperCase()}
    </span>
  );
}
