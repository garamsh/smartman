import { Suspense } from "react";

import { Study } from "./_components/study";
import { StudySkeleton } from "./_components/study-skeleton";

/** A study session over the decks `?decks=` names, comma-separated. */
export default function StudyPage({ searchParams }: PageProps<"/study">) {
  return (
    <Suspense fallback={<StudySkeleton />}>
      <Study searchParams={searchParams} />
    </Suspense>
  );
}
