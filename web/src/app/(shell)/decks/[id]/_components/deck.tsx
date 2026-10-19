import Link from "next/link";
import { notFound } from "next/navigation";

import { CardGrid, DeckTile, parseDeckId, ReadFailure, readLibrary } from "@/features/decks";
import {
  countDay,
  dayPlanOf,
  deckProgress,
  readToday,
  readyServerEngine,
  sessionMinutes,
  studyHref,
} from "@/features/study";

import { EnterLink } from "../../../_components/enter-link";

/**
 * The deck [params] names, read on the server; a deck that does not exist, or an id that names
 * none, is not found.
 */
export async function Deck({ params }: { params: Promise<{ id: string }> }) {
  const deckId = parseDeckId((await params).id);
  if (!deckId) notFound();
  const [read, studyDay] = await Promise.all([readLibrary([deckId]), readToday()]);
  if ("failure" in read) return <ReadFailure failure={read.failure} />;
  if ("failure" in studyDay) return <ReadFailure failure={studyDay.failure} />;

  const deck = read.library.decks.find((candidate) => candidate.id === deckId);
  if (!deck) notFound();
  const { cards } = read.library;
  const { states, day, pace, answers } = studyDay.today;
  const engine = await readyServerEngine();
  if ("failure" in engine) return <ReadFailure failure={engine.failure} />;
  const today = countDay(dayPlanOf(cards, states, day, answers), states);
  const total = today.review + today.fresh;
  const progress = deckProgress(cards, states);
  const share = (part: number) => (cards.length === 0 ? 0 : (part / cards.length) * 100);
  return (
    <>
      <nav aria-label="위치" className="text-secondary">
        <ol className="flex items-center gap-2">
          <li>
            <Link
              href="/decks"
              className="rounded-md text-muted underline-offset-4 hover:underline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-ink"
            >
              덱
            </Link>
          </li>
          <li aria-hidden className="text-muted">
            /
          </li>
          <li>
            <span aria-current="page" className="font-semibold">
              {deck.name}
            </span>
          </li>
        </ol>
      </nav>
      <header className="flex items-center gap-3.5">
        <DeckTile deck={deck} size="size-13 text-title lg:rounded-button" />
        <div className="flex min-w-0 flex-col">
          <h1 className="text-deck-title break-words lg:text-display">{deck.name}</h1>
          <p className="text-secondary text-muted">
            카드 {cards.length}장{deck.public ? " · 공개" : ""}
          </p>
        </div>
      </header>
      <section
        aria-label="오늘 이 덱"
        className="flex flex-wrap items-center gap-6 rounded-card bg-hero px-6 py-6 text-on-hero shadow-card lg:px-7"
      >
        <div className="flex flex-[0_1_220px] flex-col gap-1.5">
          <p className="text-secondary">오늘 할 카드</p>
          <p
            aria-label={`오늘 할 카드 ${String(total)}장, 약 ${String(sessionMinutes(today.review, today.fresh, pace))}분`}
          >
            <span className="text-figure">{total}</span>{" "}
            <span className="text-headline">
              장 · 약 {sessionMinutes(today.review, today.fresh, pace)}분
            </span>
          </p>
          {today.backlog && (
            <p className="text-secondary">밀린 복습을 마칠 때까지 새 카드는 쉬어요.</p>
          )}
        </div>
        <div className="flex min-w-0 flex-[1_1_240px] flex-col gap-2">
          <p className="text-secondary">
            {progress.mastered} / {cards.length} 익힘
          </p>
          <div
            role="img"
            aria-label={`익힘 ${String(progress.mastered)}장, 학습 중 ${String(progress.learning)}장, 새 카드 ${String(progress.fresh)}장`}
            className="flex h-2.5 gap-0.5 overflow-hidden rounded-full"
          >
            <span
              className="bg-on-hero"
              style={{ width: `${String(share(progress.mastered))}%` }}
            />
            <span
              className="bg-on-hero/60"
              style={{ width: `${String(share(progress.learning))}%` }}
            />
            <span className="flex-1 bg-on-hero/20" />
          </div>
        </div>
        {/* A deck with no card has nothing to study. */}
        {cards.length > 0 && <EnterLink href={studyHref([deck.id])} label="학습하기" />}
      </section>
      <CardGrid cards={cards} />
    </>
  );
}
