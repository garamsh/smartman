import { Suspense } from "react";

import { AdminSkeleton } from "../_components/admin-skeleton";
import { PromptsContent } from "../_components/content";

/** The extraction prompt's versions, a new one saved here, and a trial on one photo. */
export default function Page({ searchParams }: PageProps<"/admin/prompts">) {
  return (
    <>
      <h1 className="text-display">프롬프트</h1>
      <Suspense fallback={<AdminSkeleton />}>
        <PromptsContent searchParams={searchParams} />
      </Suspense>
    </>
  );
}
