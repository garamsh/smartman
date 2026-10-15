import { Suspense } from "react";

import { BrandMark } from "@/components/brand";

import { AccountLink } from "./_components/account-link";
import { Decks } from "./_components/decks";

/** The deck list a signed-in user lands on: today's cards over every deck, and each deck. */
export default function HomePage() {
  return (
    <main className="mx-auto flex min-h-dvh w-full max-w-list flex-col gap-7 px-5 py-6">
      <header className="flex min-h-11 items-center justify-between">
        <h1>
          <BrandMark mark="lockup" alt="smartman" className="h-lockup w-auto" />
        </h1>
        <Suspense>
          <AccountLink />
        </Suspense>
      </header>
      <Suspense fallback={<p className="text-muted">덱을 불러오는 중이에요.</p>}>
        <Decks />
      </Suspense>
    </main>
  );
}
