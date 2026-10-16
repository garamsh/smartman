import { notFound } from "next/navigation";

import { type DeckId, type LibraryFailure, ReadFailure, readLibrary } from "@/features/decks";
import {
  type CardStates,
  readCardStates,
  readToday,
  selectQueue,
  StudyScreen,
} from "@/features/study";

/**
 * Opens a session over the decks [searchParams] names: reads their cards, their states and
 * today's answers on the server and selects the cards left today. Decks that do not exist are
 * left out; with none left, the page is not found.
 */
export async function Study({
  searchParams,
}: {
  searchParams: Promise<Record<string, string | string[] | undefined>>;
}) {
  const { decks } = await searchParams;
  const named = typeof decks === "string" ? decks.split(",").filter(Boolean) : [];
  if (named.length === 0) notFound();
  const [read, states, today] = await Promise.all([
    readLibrary(named as DeckId[]),
    readCardStates(),
    readToday({ streak: true }),
  ]);
  if ("failure" in read) return <Failure failure={read.failure} />;
  if ("failure" in states) return <Failure failure={states.failure} />;
  if ("failure" in today) return <Failure failure={today.failure} />;
  if (!read.library.decks.some((deck) => named.includes(deck.id))) notFound();

  const { cards } = read.library;
  const { day, answers, streakBefore } = today.today;
  const queue = selectQueue(cards, states.states, day);
  const before: CardStates = {};
  for (const card of queue.cards) {
    const state = states.states[card.id];
    if (state) before[card.id] = state;
  }
  const byId = new Map(cards.map((card) => [card.id, card]));
  const own = answers.filter((answer) => byId.has(answer.cardId));
  const answeredCards = [...new Set(own.map((answer) => answer.cardId))].flatMap(
    (id) => byId.get(id) ?? [],
  );
  return (
    <StudyScreen
      plan={{
        startedAt: states.readAt,
        queue,
        before,
        today: {
          answers: own.map(({ answer, durationMs }) => ({ answer, durationMs })),
          cards: answeredCards,
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
