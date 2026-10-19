import Link from "next/link";

import { formatDate } from "../format";
import type { PublicDeck } from "../read-admin";
import { DeckActions } from "./deck-actions";
import { DeckStateChips } from "./deck-state";

/** Public decks, newest published first, each with its owner, counts, state and actions. */
export function PublicDecks({
  decks,
  timeZone,
  empty,
}: {
  decks: PublicDeck[];
  timeZone: string;
  empty: string;
}) {
  if (decks.length === 0) return <p className="text-muted">{empty}</p>;
  return (
    <ul className="flex flex-col gap-row-gap">
      {decks.map((deck) => {
        const state = { visibility: "public", hidden: deck.hidden, deleted: false } as const;
        return (
          <li key={deck.id} className="flex flex-col gap-3 rounded-row bg-surface p-4">
            <div className="flex flex-wrap items-center gap-2">
              <Link
                href={`/admin/decks/${deck.id}`}
                className="text-body-strong underline-offset-4 hover:underline focus-visible:outline-2 focus-visible:outline-ink"
              >
                {deck.name}
              </Link>
              <DeckStateChips state={state} />
            </div>
            <p className="text-caption text-muted">
              {deck.owner.name ?? deck.owner.email} · 카드 {deck.cards}장 · 가져오기 {deck.copies}회
              · 신고 {deck.reports}건
              {deck.publishedAt === null ? "" : ` · ${formatDate(deck.publishedAt, timeZone)} 공개`}
            </p>
            <DeckActions id={deck.id} name={deck.name} state={state} reports={deck.reports} />
          </li>
        );
      })}
    </ul>
  );
}
