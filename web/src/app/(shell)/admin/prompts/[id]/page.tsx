import { Suspense } from "react";

import { AdminSkeleton } from "../../_components/admin-skeleton";
import { PromptContent } from "../../_components/content";

/** One prompt version, its difference from the active one, and the actions that serve it. */
export default function Page({ params }: PageProps<"/admin/prompts/[id]">) {
  return (
    <Suspense fallback={<AdminSkeleton />}>
      <PromptContent params={params} />
    </Suspense>
  );
}
