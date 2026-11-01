import type { Metadata } from "next";
import { Suspense } from "react";

import { Today } from "./_components/today";
import { TodaySkeleton } from "./_components/today-skeleton";

export const metadata: Metadata = { title: "오늘 · 알아몰라" };

/** 오늘: today's cards over every deck, the next seven days and today's decks. */
export default function TodayPage() {
  return (
    <Suspense fallback={<TodaySkeleton />}>
      <Today />
    </Suspense>
  );
}
