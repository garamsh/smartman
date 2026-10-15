import { DeckList, ReadFailure, readDeckList, TodayHeader } from "@/features/decks";
import { countToday, readCardStates, readPace, sessionMinutes } from "@/features/study";

/**
 * Every deck with what a session over it would study now and how long it would take at the
 * user's pace, read on the server.
 */
export async function Decks() {
  const [read, states, pace] = await Promise.all([readDeckList(), readCardStates(), readPace()]);
  if ("failure" in read) return <ReadFailure failure={read.failure} />;
  if ("failure" in states) return <ReadFailure failure={states.failure} />;
  if ("failure" in pace) return <ReadFailure failure={pace.failure} />;

  const { decks, cards } = read.library;
  const all = countToday(cards, states.states, states.readAt);
  const rows = decks.map((deck) => {
    const own = cards.filter((card) => card.deckId === deck.id);
    const today = countToday(own, states.states, states.readAt);
    return { deck, cards: own.length, today: today.review + today.fresh };
  });
  return (
    <>
      <TodayHeader
        decks={decks.map((deck) => deck.id)}
        review={all.review}
        fresh={all.fresh}
        backlog={all.backlog}
        minutes={sessionMinutes(all.review + all.fresh, pace.perCardMs)}
      />
      <DeckList rows={rows} />
    </>
  );
}
