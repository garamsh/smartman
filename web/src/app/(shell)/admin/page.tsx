import { Suspense } from "react";

import { OverviewContent } from "./_components/content";
import { AdminSkeleton } from "./_components/admin-skeleton";

/** The admin area's overview: users, study, and photo extractions with their estimated cost. */
export default function Page() {
  return (
    <>
      <h1 className="text-display">관리</h1>
      <Suspense fallback={<AdminSkeleton />}>
        <OverviewContent />
      </Suspense>
    </>
  );
}
