import { Suspense } from "react";

import { AuditContent } from "../_components/content";
import { AdminSkeleton } from "../_components/admin-skeleton";

/** Every admin write, newest first. */
export default function Page() {
  return (
    <>
      <h1 className="text-display">작업 기록</h1>
      <Suspense fallback={<AdminSkeleton />}>
        <AuditContent />
      </Suspense>
    </>
  );
}
