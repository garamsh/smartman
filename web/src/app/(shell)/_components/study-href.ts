/** The study page's address for a session over [decks]. */
export function studyHref(decks: readonly string[]): string {
  return `/study?decks=${decks.map(encodeURIComponent).join(",")}`;
}
