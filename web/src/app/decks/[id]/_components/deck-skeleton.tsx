import { Skeleton, SkeletonLine } from "@/components/skeleton";

/**
 * A deck's page while it is read: the back link's place, the name, the three pills, the study
 * button, the search and four card rows, in their sizes.
 */
export function DeckSkeleton() {
  return (
    <Skeleton status="덱을 불러오는 중이에요." className="flex flex-col gap-5">
      <span className="size-tap-target" />
      <div className="flex flex-col gap-4">
        <SkeletonLine text="text-deck-title" width="w-1/2" />
        <div className="flex gap-2">
          {[0, 1, 2].map((pill) => (
            <span key={pill} className="rounded-full bg-surface px-4 py-2">
              <SkeletonLine text="text-section" width="w-12" />
            </span>
          ))}
        </div>
      </div>
      <span className="min-h-cta rounded-button bg-hairline" />
      <div className="flex flex-col gap-3">
        <span className="h-search rounded-field border border-outline bg-surface" />
        <div className="divide-y divide-hairline overflow-hidden rounded-row bg-surface">
          {[0, 1, 2, 3].map((row) => (
            <div key={row} className="grid grid-cols-2 divide-x divide-hairline">
              <span className="p-4">
                <SkeletonLine text="text-label" width="w-1/2" />
              </span>
              <span className="p-4">
                <SkeletonLine text="text-secondary" width="w-2/3" />
              </span>
            </div>
          ))}
        </div>
      </div>
    </Skeleton>
  );
}
