import { Suspense } from "react";

import { ReportsContent } from "../_components/content";
import { AdminSkeleton } from "../_components/admin-skeleton";

/** The reported decks, with their reasons and the moderation actions. */
export default function Page() {
  return (
    <>
      <h1 className="text-display">신고</h1>
      <Suspense fallback={<AdminSkeleton />}>
        <ReportsContent />
      </Suspense>
    </>
  );
}
