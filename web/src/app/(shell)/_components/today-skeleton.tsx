import { Skeleton, SkeletonLine } from "@/design/skeleton";

/**
 * The 오늘 page while it is read: the heading, the today card with its ring and button, and the
 * last seven study days with their line, in their sizes.
 */
export function TodaySkeleton() {
  return (
    <Skeleton status="오늘 할 카드를 불러오는 중이에요." className="flex flex-col gap-5">
      <SkeletonLine text="text-display" width="w-24" />
      <div className="grid gap-4 lg:grid-cols-2">
        <div className="flex flex-wrap items-center gap-6 rounded-card bg-hero p-6 shadow-card lg:col-span-2 lg:p-7">
          <div className="flex min-w-0 flex-[1_1_220px] flex-col gap-2">
            <SkeletonLine text="text-label" width="w-24" tone="bg-on-hero/20" />
            <SkeletonLine text="text-figure" width="w-40" tone="bg-on-hero/20" />
            <SkeletonLine text="text-secondary" width="w-48" tone="bg-on-hero/20" />
          </div>
          <span className="size-24 shrink-0 rounded-full border-8 border-on-hero/20" />
          <span className="min-h-cta flex-[1_1_100%] rounded-button bg-on-hero/20 sm:flex-[0_1_240px]" />
        </div>
        <div className="flex flex-col gap-3.5 rounded-card bg-surface p-5">
          <SkeletonLine text="text-body-strong" width="w-24" />
          <SkeletonLine text="text-caption" width="w-40" />
          <span className="h-28" />
        </div>
      </div>
    </Skeleton>
  );
}
