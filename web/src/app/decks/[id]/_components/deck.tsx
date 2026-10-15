import { ChevronLeft } from "lucide-react";
import Link from "next/link";
import { notFound } from "next/navigation";

import { CardList, type DeckId, ReadFailure, readLibrary, StudyLink } from "@/features/decks";
import { countToday, readCardStates } from "@/features/study";

/** The deck [params] names, read on the server; a deck that does not exist is not found. */
export async function Deck({ params }: { params: Promise<{ id: string }> }) {
  const { id } = await params;
  const deckId = id as DeckId;
  const [read, states] = await Promise.all([readLibrary([deckId]), readCardStates()]);
  if ("failure" in read) return <ReadFailure failure={read.failure} />;
  if ("failure" in states) return <ReadFailure failure={states.failure} />;

  const deck = read.library.decks.find((candidate) => candidate.id === deckId);
  if (!deck) notFound();
  const { cards } = read.library;
  const today = countToday(cards, states.states, states.readAt);
  const pills = [
    `카드 ${String(cards.length)}`,
    `복습 ${String(today.review)}`,
    `새 카드 ${String(today.fresh)}`,
  ];
  return (
    <>
      <Link
        href="/"
        aria-label="덱 목록"
        className="-ml-3 flex size-11 items-center justify-center rounded-full text-ink focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-ink"
      >
        <ChevronLeft aria-hidden className="size-6" strokeWidth={2} />
      </Link>
      <div className="flex flex-col gap-4">
        <h1 className="text-deck-title">{deck.name}</h1>
        <ul aria-label="개수" className="flex flex-wrap gap-2">
          {pills.map((pill) => (
            <li key={pill} className="rounded-full bg-surface px-4 py-2 text-section">
              {pill}
            </li>
          ))}
        </ul>
      </div>
      <StudyLink
        decks={[deck.id]}
        cards={today.review + today.fresh}
        label={`학습하기 · ${String(today.review + today.fresh)}장`}
      />
      <CardList cards={cards} />
    </>
  );
}
