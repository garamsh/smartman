import { ChevronLeft } from "lucide-react";
import Link from "next/link";
import { notFound } from "next/navigation";

import {
  CardList,
  type DeckId,
  PublicChip,
  ReadFailure,
  readLibrary,
  StudyLink,
} from "@/features/decks";
import { countToday, readToday } from "@/features/study";

/** The deck [params] names, read on the server; a deck that does not exist is not found. */
export async function Deck({ params }: { params: Promise<{ id: string }> }) {
  const { id } = await params;
  const deckId = id as DeckId;
  const [read, studyDay] = await Promise.all([readLibrary([deckId]), readToday()]);
  if ("failure" in read) return <ReadFailure failure={read.failure} />;
  if ("failure" in studyDay) return <ReadFailure failure={studyDay.failure} />;

  const deck = read.library.decks.find((candidate) => candidate.id === deckId);
  if (!deck) notFound();
  const { cards } = read.library;
  const today = countToday(cards, studyDay.today.states, studyDay.today.day);
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
        className="-ml-3 flex size-tap-target items-center justify-center rounded-full text-ink focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-ink"
      >
        <ChevronLeft aria-hidden className="size-6" strokeWidth={2} />
      </Link>
      <div className="flex flex-col gap-4">
        <div className="flex flex-wrap items-center gap-x-3 gap-y-1">
          <h1 className="text-deck-title">{deck.name}</h1>
          {deck.public && <PublicChip />}
        </div>
        <ul aria-label="개수" className="flex flex-wrap gap-2">
          {pills.map((pill) => (
            <li key={pill} className="rounded-full bg-surface px-4 py-2 text-section">
              {pill}
            </li>
          ))}
        </ul>
        {today.backlog && (
          <p className="text-secondary text-muted">밀린 복습을 마칠 때까지 새 카드는 쉬어요.</p>
        )}
      </div>
      <StudyLink decks={[deck.id]} label={`학습하기 · ${String(today.review + today.fresh)}장`} />
      <CardList cards={cards} />
    </>
  );
}
