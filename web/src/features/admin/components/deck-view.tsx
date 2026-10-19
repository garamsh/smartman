import Link from "next/link";

import { labelOf, reasonLabels } from "../labels";
import type { AdminDeck } from "../read-admin";
import { DeckActions } from "./deck-actions";
import { DeckStateChips } from "./deck-state";

/** A deck, read-only: its owner, state, reports, actions and every live card. */
export function DeckView({ deck }: { deck: AdminDeck }) {
  return (
    <div className="flex flex-col gap-section-gap">
      <header className="flex flex-col gap-2">
        <h1 className="text-display">{deck.name}</h1>
        <DeckStateChips state={deck.state} />
        <p className="text-secondary text-muted">
          <Link
            href={`/admin/users/${deck.owner.id}`}
            className="underline underline-offset-4 focus-visible:outline-2 focus-visible:outline-ink"
          >
            {deck.owner.email}
          </Link>
          {deck.owner.name === null ? "" : ` (${deck.owner.name})`} · 카드 {deck.cards.length}장 ·
          가져오기 {deck.copies}회 · 신고 {deck.reports}건
          {deck.reasons.length === 0
            ? ""
            : ` · ${deck.reasons.map((reason) => labelOf(reasonLabels, reason)).join(", ")}`}
        </p>
        {deck.description !== null && <p className="text-body">{deck.description}</p>}
      </header>
      <DeckActions id={deck.id} name={deck.name} state={deck.state} reports={deck.reports} />
      <section aria-label="카드" className="flex flex-col gap-3">
        <h2 className="text-section">카드</h2>
        {deck.cards.length === 0 ? (
          <p className="text-muted">카드가 없어요.</p>
        ) : (
          <ul className="flex flex-col gap-2">
            {deck.cards.map((card) => (
              <li
                key={card.id}
                className="grid grid-cols-2 gap-4 rounded-row bg-surface px-4 py-3 text-secondary"
              >
                <span className="break-words">{card.front}</span>
                <span className="break-words text-ink-2">{card.back}</span>
              </li>
            ))}
          </ul>
        )}
      </section>
    </div>
  );
}
