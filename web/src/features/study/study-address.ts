import { type DeckId, parseDeckId } from "@/features/decks";

/** The study page's address for a session over [decks]. */
export function studyHref(decks: readonly string[]): string {
  return `/study?decks=${decks.map(encodeURIComponent).join(",")}`;
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
