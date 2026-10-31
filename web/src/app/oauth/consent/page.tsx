import type { Metadata } from "next";
import { Suspense } from "react";

import { Consent } from "./_components/consent";
import { ConsentSkeleton } from "./_components/consent-skeleton";

export const metadata: Metadata = { title: "AI 연결 · smartman" };

/**
 * The consent page Supabase Auth's OAuth server opens for an AI app connecting to the user's
 * account (ADR 0126), outside the shell as `/login` is: the request, read with the session, and
 * its answer.
 */
export default function ConsentPage({ searchParams }: PageProps<"/oauth/consent">) {
  return (
    <main className="mx-auto flex min-h-dvh w-full max-w-list flex-col gap-section-gap px-gutter py-10">
      <Suspense fallback={<ConsentSkeleton />}>
        <Consent searchParams={searchParams} />
      </Suspense>
    </main>
  );
}
