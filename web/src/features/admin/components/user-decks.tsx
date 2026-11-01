import Link from "next/link";

import type { UserDeck } from "../read-admin";
import { DeckStateChips } from "./deck-state";

/** Every live deck of a user, public or private, each opening the deck read-only. */
export function UserDecks({ decks }: { decks: UserDeck[] }) {
  return (
    <section aria-label="덱" className="flex flex-col gap-3">
      <h2 className="text-section">덱</h2>
      {decks.length === 0 ? (
        <p className="text-muted">덱이 없어요.</p>
      ) : (
        <ul className="flex flex-col gap-2">
          {decks.map((deck) => (
            <li key={deck.id}>
              <Link
                href={`/admin/decks/${deck.id}`}
                className="flex min-h-13 items-center justify-between gap-3 rounded-row bg-surface px-4 py-3 focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-ink"
              >
                <span className="flex min-w-0 items-center gap-2">
                  <span className="truncate text-body-strong">{deck.name}</span>
                  <DeckStateChips
                    state={{ visibility: deck.visibility, hidden: deck.hidden, deleted: false }}
                  />
                  {deck.removed && (
                    <span className="rounded-full bg-tint-red px-2 py-0.5 text-micro font-semibold text-dont-know-text">
                      공유 삭제
                    </span>
                  )}
                </span>
                <span className="text-caption whitespace-nowrap text-muted">
                  카드 {deck.cards}장
                </span>
              </Link>
            </li>
          ))}
        </ul>
      )}
    </section>
  );
}
