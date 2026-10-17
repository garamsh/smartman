import type { Metadata } from "next";
import { Suspense } from "react";

import { Mascot } from "@/design/brand";
import { LegalLinks } from "@/features/legal";

import { Profile } from "./_components/profile";
import { ProfileSkeleton } from "./_components/profile-skeleton";

export const metadata: Metadata = { title: "계정 · smartman" };

/** The signed-in account: who it is, the theme, signing out, and the legal links. */
export default function AccountPage() {
  return (
    <div className="flex w-full max-w-list flex-1 flex-col gap-section-gap">
      <h1 className="text-display">계정과 설정</h1>
      <Suspense fallback={<ProfileSkeleton />}>
        <Profile />
      </Suspense>
      <footer className="mt-auto flex flex-col items-center gap-2 pt-10">
        <span className="opacity-50">
          <Mascot className="size-mascot-small" />
        </span>
        <LegalLinks />
      </footer>
    </div>
  );
}
