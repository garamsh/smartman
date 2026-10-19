import { Suspense } from "react";

import { AdminSkeleton } from "../_components/admin-skeleton";
import { PlansContent } from "../_components/content";

/** Each plan's model and daily limit, set here. */
export default function Page() {
  return (
    <>
      <h1 className="text-display">요금제</h1>
      <Suspense fallback={<AdminSkeleton />}>
        <PlansContent />
      </Suspense>
    </>
  );
}
