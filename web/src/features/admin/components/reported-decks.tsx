import Link from "next/link";

import { formatTime } from "../format";
import { labelOf, reasonLabels } from "../labels";
import type { ReportedDeck } from "../read-admin";
import { DeckActions } from "./deck-actions";
import { DeckStateChips } from "./deck-state";

/** The reported decks, the latest report first, each with its reasons, state and actions. */
export function ReportedDecks({ decks, timeZone }: { decks: ReportedDeck[]; timeZone: string }) {
  if (decks.length === 0) return <p className="text-muted">신고된 덱이 없어요.</p>;
  return (
    <ul className="flex flex-col gap-row-gap">
      {decks.map((deck) => (
        <li key={deck.id} className="flex flex-col gap-3 rounded-row bg-surface p-4">
          <div className="flex flex-wrap items-center gap-2">
            <Link
              href={`/admin/decks/${deck.id}`}
              className="text-body-strong underline-offset-4 hover:underline focus-visible:outline-2 focus-visible:outline-ink"
            >
              {deck.name}
            </Link>
            <DeckStateChips state={deck.state} />
          </div>
          <p className="text-caption text-muted">
            {deck.owner.name ?? deck.owner.email} · 신고 {deck.reports}건 ·{" "}
            {deck.reasons.map((reason) => labelOf(reasonLabels, reason)).join(", ")} · 마지막 신고{" "}
            {formatTime(deck.lastReportedAt, timeZone)}
          </p>
          <DeckActions id={deck.id} name={deck.name} state={deck.state} reports={deck.reports} />
        </li>
      ))}
    </ul>
  );
}
