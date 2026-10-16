import { Skeleton, SkeletonLine } from "@/design/skeleton";

/** The home page while its decks are read: the today card and three deck rows, in their sizes. */
export function DecksSkeleton() {
  return (
    <Skeleton status="덱을 불러오는 중이에요." className="flex flex-col gap-section-gap">
      <div className="flex flex-col gap-5 rounded-card bg-hero p-6 shadow-card">
        <div className="flex flex-col gap-1">
          <SkeletonLine text="text-section" width="w-1/4" tone="bg-on-hero/20" />
          <SkeletonLine text="text-figure" width="w-1/5" tone="bg-on-hero/20" />
          <SkeletonLine text="text-secondary" width="w-1/2" tone="bg-on-hero/20" />
        </div>
        <span className="min-h-button rounded-button bg-on-hero/20" />
      </div>
      <div className="flex flex-col gap-3">
        <SkeletonLine text="text-section" width="w-16" />
        <div className="flex flex-col gap-row-gap">
          {[0, 1, 2].map((row) => (
            <div
              key={row}
              className="flex min-h-13 items-center gap-3 rounded-row bg-surface py-3 pr-3 pl-4"
            >
              <span className="size-deck-tile shrink-0 rounded-field bg-hairline" />
              <span className="flex flex-1 flex-col">
                <SkeletonLine text="text-body-strong" width="w-2/5" />
                <SkeletonLine text="text-caption" width="w-1/5" />
              </span>
            </div>
          ))}
        </div>
      </div>
    </Skeleton>
  );
}
