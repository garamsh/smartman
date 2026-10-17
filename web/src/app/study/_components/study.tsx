import { notFound } from "next/navigation";

import {
  type DeckId,
  describeContent,
  type LibraryFailure,
  ReadFailure,
  readLibrary,
} from "@/features/decks";
import { type CardStates, newCards, readToday, selectQueue, StudyScreen } from "@/features/study";

/**
 * Opens a session over the decks [searchParams] names: reads their cards, their states and
 * today's answers on the server and selects the cards left today and the new cards past them.
 * Decks that do not exist are left out; with none left, the page is not found.
 */
export async function Study({
  searchParams,
}: {
  searchParams: Promise<Record<string, string | string[] | undefined>>;
}) {
  const { decks } = await searchParams;
  const named = typeof decks === "string" ? decks.split(",").filter(Boolean) : [];
  if (named.length === 0) notFound();
  const [read, today] = await Promise.all([
    readLibrary(named as DeckId[]),
    readToday({ streak: true }),
  ]);
  if ("failure" in read) return <Failure failure={read.failure} />;
  if ("failure" in today) return <Failure failure={today.failure} />;
  if (!read.library.decks.some((deck) => named.includes(deck.id))) notFound();

  // Each side's text for the client, which cannot import decks' entry point.
  const cards = read.library.cards.map((card) => ({
    ...card,
    text: { front: describeContent(card.front), back: describeContent(card.back) },
  }));
  const { day, answers, states, readAt, pace, streakBefore } = today.today;
  const queue = selectQueue(cards, states, day);
  const taken = new Set(queue.cards.map((card) => card.id));
  const more = newCards(cards, states).filter((card) => !taken.has(card.id));
  const before: CardStates = {};
  for (const card of queue.cards) {
    const state = states[card.id];
    if (state) before[card.id] = state;
  }
  const ids = new Set(cards.map((card) => card.id));
  const own = answers.filter((answer) => ids.has(answer.cardId));
  return (
    <StudyScreen
      plan={{
        startedAt: readAt,
        queue,
        more,
        before,
        pace,
        today: {
          answers: own.map(({ answer, durationMs }) => ({ answer, durationMs })),
          answeredAnyDeck: answers.length > 0,
          streakBefore,
        },
      }}
    />
  );
}

function Failure({ failure }: { failure: LibraryFailure }) {
  return (
    <main className="mx-auto flex min-h-dvh w-full max-w-3xl px-gutter py-6">
      <ReadFailure failure={failure} />
    </main>
  );
}
