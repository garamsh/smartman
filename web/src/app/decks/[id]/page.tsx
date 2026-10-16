import { Suspense } from "react";

import { Deck } from "./_components/deck";
import { DeckSkeleton } from "./_components/deck-skeleton";

/** One deck: its name, today's line, its study button and its cards. */
export default function DeckPage({ params }: PageProps<"/decks/[id]">) {
  return (
    <main className="mx-auto flex min-h-dvh w-full max-w-list flex-col gap-5 px-gutter py-6">
      <Suspense fallback={<DeckSkeleton />}>
        <Deck params={params} />
      </Suspense>
    </main>
  );
}
