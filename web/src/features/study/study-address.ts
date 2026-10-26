import { type DeckId, parseDeckId } from "@/features/decks";

/**
 * The study page's address for a session over [decks], marked as opened from the deck's own page
 * when [from] is `"deck"`, so the session returns there.
 */
export function studyHref(decks: readonly string[], from?: "deck"): string {
  const address = `/study?decks=${decks.map(encodeURIComponent).join(",")}`;
  return from === "deck" ? `${address}&from=deck` : address;
}

/**
 * Where the session leaves for: the page of the one deck [decks] names when the `from` parameter
 * is `deck`, as [studyHref] writes it, and 오늘 otherwise. The address is built here from a deck
 * id `parseDeckId` read, never taken from the parameter, so it is always this site's own page.
 */
export function studyReturn(from: string | string[] | undefined, decks: readonly DeckId[]): string {
  const [deck] = decks;
  return from === "deck" && deck !== undefined && decks.length === 1
    ? `/decks/${encodeURIComponent(deck)}`
    : "/";
}

/**
 * The decks the study page's `decks` parameter names, as [studyHref] writes it, each read through
 * `parseDeckId`, so an id that is not a uuid is left out; none when it is absent or repeated.
 */
export function studyDecks(decks: string | string[] | undefined): DeckId[] {
  return (typeof decks === "string" ? decks.split(",") : [])
    .map(parseDeckId)
    .filter((id) => id !== null);
}
