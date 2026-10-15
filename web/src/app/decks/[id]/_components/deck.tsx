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
  return (
    <>
      <Link href="/" className="self-start font-semibold text-muted underline">
        덱 목록
      </Link>
      <div className="flex flex-col gap-1">
        <h1 className="text-3xl font-bold">{deck.name}</h1>
        <p className="text-muted">
          카드 {cards.length}장 · 오늘 복습 {today.review} · 새 카드 {today.fresh}
        </p>
      </div>
      <StudyLink
        decks={[deck.id]}
        cards={today.review + today.fresh}
        label={`학습 · ${String(today.review + today.fresh)}장`}
      />
      <CardList cards={cards} />
    </>
  );
}
