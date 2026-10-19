import { Suspense } from "react";

import { AdminsContent } from "../_components/content";
import { AdminSkeleton } from "../_components/admin-skeleton";

/** The admins, with granting and revoking. */
export default function Page() {
  return (
    <>
      <h1 className="text-display">관리자</h1>
      <Suspense fallback={<AdminSkeleton />}>
        <AdminsContent />
      </Suspense>
    </>
  );
}
