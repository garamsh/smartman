import { Suspense } from "react";

import { Account } from "./_components/account";

/** The home page a signed-in user lands on. */
export default function HomePage() {
  return (
    <main className="mx-auto flex min-h-dvh w-full max-w-sm flex-col justify-center gap-8 px-6">
      <h1 className="text-3xl font-bold">smartman</h1>
      <Suspense>
        <Account />
      </Suspense>
    </main>
  );
}
