import { DeckList, EmptyHome, ReadFailure, readDeckList } from "@/features/decks";
import { countToday, deckProgress, readToday } from "@/features/study";

/** Every deck with what a session over it would study now and its progress, read on the server. */
export async function Decks() {
  const [read, today] = await Promise.all([readDeckList(), readToday()]);
  if ("failure" in read) return <ReadFailure failure={read.failure} />;
  if ("failure" in today) return <ReadFailure failure={today.failure} />;
  const { decks, cards } = read.library;
  const { day, states } = today.today;
  const heading = (
    <h1 className="text-display">
      내 덱 <span className="text-muted">{decks.length}</span>
    </h1>
  );
  if (decks.length === 0) {
    return (
      <>
        {heading}
        <EmptyHome />
      </>
    );
  }
  const rows = decks.map((deck) => {
    const own = cards.filter((card) => card.deckId === deck.id);
    const left = countToday(own, states, day);
    const { mastered, learning } = deckProgress(own, states);
    return { deck, cards: own.length, today: left.review + left.fresh, mastered, learning };
  });
  return (
    <>
      {heading}
      <DeckList rows={rows} />
    </>
  );
}
