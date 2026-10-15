import { Suspense } from "react";

import { Deck } from "./_components/deck";

/** One deck: its name, today's line, its study button and its cards. */
export default function DeckPage({ params }: PageProps<"/decks/[id]">) {
  return (
    <main className="mx-auto flex min-h-dvh w-full max-w-list flex-col gap-5 px-5 py-6">
      <Suspense fallback={<p className="text-muted">덱을 불러오는 중이에요.</p>}>
        <Deck params={params} />
      </Suspense>
    </main>
  );
}
