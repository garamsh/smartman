import { Suspense } from "react";

import { Account } from "./_components/account";
import { Decks } from "./_components/decks";

/** The deck list a signed-in user lands on: today's cards over every deck, and each deck. */
export default function HomePage() {
  return (
    <main className="mx-auto flex min-h-dvh w-full max-w-2xl flex-col gap-6 px-5 py-8">
      <h1 className="text-3xl font-bold">덱</h1>
      <Suspense fallback={<p className="text-muted">덱을 불러오는 중이에요.</p>}>
        <Decks />
      </Suspense>
      <Suspense>
        <Account />
      </Suspense>
    </main>
  );
}
