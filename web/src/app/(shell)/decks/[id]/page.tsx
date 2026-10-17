import { Suspense } from "react";

import { Deck } from "./_components/deck";
import { DeckSkeleton } from "./_components/deck-skeleton";

/** One deck: where it sits, its header, today's card for it with its progress, and its cards. */
export default function DeckPage({ params }: PageProps<"/decks/[id]">) {
  return (
    <Suspense fallback={<DeckSkeleton />}>
      <Deck params={params} />
    </Suspense>
  );
}
