import { Suspense } from "react";

import { ExtractionsContent } from "../_components/content";
import { AdminSkeleton } from "../_components/admin-skeleton";

/** Whether photo import works: each recorded extraction's outcome and the failure rates. */
export default function Page({ searchParams }: PageProps<"/admin/extractions">) {
  return (
    <>
      <h1 className="text-display">추출 결과</h1>
      <Suspense fallback={<AdminSkeleton />}>
        <ExtractionsContent searchParams={searchParams} />
      </Suspense>
    </>
  );
}
