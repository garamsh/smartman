import type { Metadata } from "next";
import { Suspense } from "react";

import { Decks } from "./_components/decks";
import { DecksSkeleton } from "./_components/decks-skeleton";

export const metadata: Metadata = { title: "덱 · 알아몰라" };

/** 덱: every deck, with a search. */
export default function DecksPage() {
  return (
    <Suspense fallback={<DecksSkeleton />}>
      <Decks />
    </Suspense>
  );
}
