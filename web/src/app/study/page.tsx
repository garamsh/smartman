import { Suspense } from "react";

import { Study } from "./_components/study";

/** A study session over the decks `?decks=` names, comma-separated. */
export default function StudyPage({ searchParams }: PageProps<"/study">) {
  return (
    <Suspense
      fallback={
        <main className="mx-auto flex min-h-dvh w-full max-w-3xl px-gutter py-6">
          <p className="text-muted">카드를 불러오는 중이에요.</p>
        </main>
      }
    >
      <Study searchParams={searchParams} />
    </Suspense>
  );
}
