import Link from "next/link";

import type { Deck } from "../library";

/** A deck as its row shows it: its card count, and what a session over it would study now. */
export type DeckRow = { deck: Deck; cards: number; today: number };

/** The decks, each a row that opens the deck, with its card count and today's chip. */
export function DeckList({ rows }: { rows: DeckRow[] }) {
  return (
    <section aria-labelledby="deck-list-title" className="flex flex-col gap-3">
      <h2 id="deck-list-title" className="text-sm font-semibold text-muted">
        내 덱 {rows.length}
      </h2>
      {rows.length === 0 ? (
        <p className="text-muted">아직 덱이 없습니다. 휴대폰 앱에서 덱을 만들면 여기에 나타나요.</p>
      ) : (
        <ul className="flex flex-col gap-2">
          {rows.map(({ deck, cards, today }) => (
            <li key={deck.id}>
              <Link
                href={`/decks/${encodeURIComponent(deck.id)}`}
                aria-label={`${deck.name}, 카드 ${String(cards)}장${today > 0 ? `, 오늘 ${String(today)}` : ""}`}
                className="flex min-h-13 items-center gap-3 rounded-row bg-surface px-5 py-3 focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-ink"
              >
                <span className="flex flex-1 flex-col">
                  <span className="font-semibold">{deck.name}</span>
                  <span className="text-sm text-muted">카드 {cards}장</span>
                </span>
                {today > 0 && (
                  <span className="rounded-full bg-know px-3 py-1 text-sm font-semibold text-on-know">
                    오늘 {today}
                  </span>
                )}
                <span aria-hidden className="text-muted">
                  ›
                </span>
              </Link>
            </li>
          ))}
        </ul>
      )}
    </section>
  );
}
