import { ChevronRight } from "lucide-react";
import Link from "next/link";

import { deckTint } from "../deck-tint";
import type { Deck } from "../library";

/** A deck as its row shows it: its card count, and what a session over it would study now. */
export type DeckRow = { deck: Deck; cards: number; today: number };

/**
 * The decks, each a row that opens the deck: its initial on a tinted tile, its name and card
 * count, "공개" when it is published, today's chip, and a chevron.
 */
export function DeckList({ rows }: { rows: DeckRow[] }) {
  return (
    <section aria-labelledby="deck-list-title" className="flex flex-col gap-3">
      <h2 id="deck-list-title" className="text-section text-ink-2">
        내 덱 {rows.length}
      </h2>
      {rows.length === 0 ? (
        <p className="text-muted">아직 덱이 없어요. 휴대폰 앱에서 덱을 만들면 여기에 나타나요.</p>
      ) : (
        <ul className="flex flex-col gap-row-gap">
          {rows.map(({ deck, cards, today }) => (
            <li key={deck.id}>
              <Link
                href={`/decks/${encodeURIComponent(deck.id)}`}
                aria-label={`${deck.name}, 카드 ${String(cards)}장${deck.public ? ", 공개" : ""}${today > 0 ? `, 오늘 ${String(today)}` : ""}`}
                className="flex min-h-13 items-center gap-3 rounded-row bg-surface py-3 pr-3 pl-4 focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-ink"
              >
                <span
                  aria-hidden
                  className={`flex size-deck-tile shrink-0 items-center justify-center rounded-field text-headline ${deckTint(deck.id)}`}
                >
                  {deck.name.trim().charAt(0).toLocaleUpperCase()}
                </span>
                <span className="flex flex-1 flex-col">
                  <span className="text-body-strong">{deck.name}</span>
                  <span className="text-caption text-muted">카드 {cards}장</span>
                </span>
                {deck.public && <PublicChip />}
                {today > 0 && (
                  <span className="rounded-full bg-brand-tint px-3 py-1 text-micro font-semibold text-ink">
                    오늘 {today}
                  </span>
                )}
                <ChevronRight aria-hidden className="size-5 text-muted" strokeWidth={2} />
              </Link>
            </li>
          ))}
        </ul>
      )}
    </section>
  );
}

/** The chip beside a deck its owner published, as the phone draws it. */
export function PublicChip() {
  return (
    <span className="shrink-0 rounded-full border border-outline bg-surface px-3 py-1 text-micro font-semibold text-ink">
      공개
    </span>
  );
}
