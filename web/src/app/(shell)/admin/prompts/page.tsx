import { Suspense } from "react";

import { AdminSkeleton } from "../_components/admin-skeleton";
import { PromptsContent } from "../_components/content";

/** The extraction prompt's versions, a new one saved here, and a trial on one photo. */
export default function Page({ searchParams }: PageProps<"/admin/prompts">) {
  return (
    <>
      <h1 className="text-display">프롬프트</h1>
      <p className="text-caption text-muted">
        모든 버전 뒤에는 함수에 고정된 출력 계약(카드의 필드와 규칙)이 함께 보내져요.
      </p>
      <Suspense fallback={<AdminSkeleton />}>
        <PromptsContent searchParams={searchParams} />
      </Suspense>
    </>
  );
}
