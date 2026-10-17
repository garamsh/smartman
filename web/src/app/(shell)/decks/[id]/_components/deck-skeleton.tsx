import { Skeleton, SkeletonLine } from "@/design/skeleton";

/**
 * A deck's page while it is read: the breadcrumb, the header, the navy card with its button,
 * the search, the row above the cards and four cards, in their sizes.
 */
export function DeckSkeleton() {
  return (
    <Skeleton status="덱을 불러오는 중이에요." className="flex flex-col gap-5">
      <SkeletonLine text="text-secondary" width="w-24" />
      <div className="flex items-center gap-3.5">
        <span className="size-13 shrink-0 rounded-field bg-hairline" />
        <div className="flex flex-1 flex-col">
          <SkeletonLine text="text-deck-title lg:text-display" width="w-1/3" />
          <SkeletonLine text="text-secondary" width="w-20" />
        </div>
      </div>
      <div className="flex flex-wrap items-center gap-6 rounded-card bg-hero px-6 py-6 shadow-card lg:px-7">
        <div className="flex flex-[0_1_220px] flex-col gap-1.5">
          <SkeletonLine text="text-secondary" width="w-24" tone="bg-on-hero/20" />
          <SkeletonLine text="text-figure" width="w-32" tone="bg-on-hero/20" />
        </div>
        <div className="flex min-w-0 flex-[1_1_240px] flex-col gap-2">
          <SkeletonLine text="text-secondary" width="w-20" tone="bg-on-hero/20" />
          <span className="h-2.5 rounded-full bg-on-hero/20" />
        </div>
        <span className="min-h-cta flex-[1_1_100%] rounded-button bg-on-hero/20 sm:flex-[0_1_240px]" />
      </div>
      <div className="flex flex-col gap-3">
        <span className="h-search rounded-field border border-outline bg-surface" />
        <span className="min-h-tap-target" />
        <div className="grid grid-cols-[repeat(auto-fill,minmax(240px,1fr))] gap-2.5">
          {[0, 1, 2, 3].map((card) => (
            <div key={card} className="flex min-h-23 flex-col gap-2 rounded-row bg-surface p-4">
              <SkeletonLine text="text-headline" width="w-1/2" />
              <span className="h-4.5 w-3/5 rounded-md bg-hairline" />
            </div>
          ))}
        </div>
      </div>
    </Skeleton>
  );
}
