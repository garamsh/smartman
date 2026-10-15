import { ChevronLeft } from "lucide-react";
import type { Metadata } from "next";
import Link from "next/link";
import { Suspense } from "react";

import { Mascot } from "@/components/brand";
import { LegalLinks } from "@/components/legal-links";

import { Profile } from "./_components/profile";

export const metadata: Metadata = { title: "계정 · smartman" };

/** The signed-in account: who it is, signing out, and the legal links. */
export default function AccountPage() {
  return (
    <main className="mx-auto flex min-h-dvh w-full max-w-list flex-col gap-7 px-5 py-6">
      <header className="flex items-center gap-1">
        <Link
          href="/"
          aria-label="덱 목록"
          className="-ml-3 flex size-11 items-center justify-center rounded-full text-ink focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-ink"
        >
          <ChevronLeft aria-hidden className="size-6" strokeWidth={2} />
        </Link>
        <h1 className="text-title">계정</h1>
      </header>
      <Suspense fallback={<p className="text-muted">계정을 불러오는 중이에요.</p>}>
        <Profile />
      </Suspense>
      <footer className="mt-auto flex flex-col items-center gap-2 pt-10">
        <span className="opacity-50">
          <Mascot className="size-7" />
        </span>
        <LegalLinks />
      </footer>
    </main>
  );
}
