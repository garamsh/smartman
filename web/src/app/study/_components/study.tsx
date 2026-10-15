import { notFound } from "next/navigation";

import { type DeckId, type LibraryFailure, ReadFailure, readLibrary } from "@/features/decks";
import { type CardStates, readCardStates, selectQueue, StudyScreen } from "@/features/study";

/**
 * Opens a session over the decks [searchParams] names: reads their cards and states on the
 * server and selects the queue now. Decks that do not exist are left out; with none left, the
 * page is not found.
 */
export async function Study({
  searchParams,
}: {
  searchParams: Promise<Record<string, string | string[] | undefined>>;
}) {
  const { decks } = await searchParams;
  const named = typeof decks === "string" ? decks.split(",").filter(Boolean) : [];
  if (named.length === 0) notFound();
  const [read, states] = await Promise.all([readLibrary(named as DeckId[]), readCardStates()]);
  if ("failure" in read) return <Failure failure={read.failure} />;
  if ("failure" in states) return <Failure failure={states.failure} />;
  if (!read.library.decks.some((deck) => named.includes(deck.id))) notFound();

  const cards = selectQueue(read.library.cards, states.states, states.readAt);
  const before: CardStates = {};
  for (const card of cards) {
    const state = states.states[card.id];
    if (state) before[card.id] = state;
  }
  return <StudyScreen plan={{ startedAt: states.readAt, cards, before }} />;
}

function Failure({ failure }: { failure: LibraryFailure }) {
  return (
    <main className="mx-auto flex min-h-dvh w-full max-w-3xl px-5 py-6">
      <ReadFailure failure={failure} />
    </main>
  );
}
