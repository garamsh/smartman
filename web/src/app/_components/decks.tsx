import { DeckList, EmptyHome, ReadFailure, readDeckList, TodayHeader } from "@/features/decks";
import { countToday, readCardStates, readPace, readToday, sessionMinutes } from "@/features/study";

/**
 * Every deck with the cards left today for a session over it and how long they would take at
 * the user's pace, read on the server; with no deck, the first-run invitation.
 */
export async function Decks() {
  const [read, states, pace, today] = await Promise.all([
    readDeckList(),
    readCardStates(),
    readPace(),
    readToday(),
  ]);
  if ("failure" in read) return <ReadFailure failure={read.failure} />;
  if ("failure" in states) return <ReadFailure failure={states.failure} />;
  if ("failure" in pace) return <ReadFailure failure={pace.failure} />;
  if ("failure" in today) return <ReadFailure failure={today.failure} />;
  const { day } = today.today;

  const { decks, cards } = read.library;
  if (decks.length === 0) return <EmptyHome />;
  const all = countToday(cards, states.states, day);
  const rows = decks.map((deck) => {
    const own = cards.filter((card) => card.deckId === deck.id);
    const today = countToday(own, states.states, day);
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
