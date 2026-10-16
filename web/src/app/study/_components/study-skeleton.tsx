import { Skeleton, SkeletonLine } from "@/components/skeleton";

/**
 * The study page while its cards are read: the header with the progress bar, the current card
 * and the two answer buttons, in their sizes.
 */
export function StudySkeleton() {
  return (
    <main className="mx-auto w-full max-w-6xl px-gutter py-6">
      <Skeleton status="카드를 불러오는 중이에요." className="flex flex-col gap-6">
        <div className="flex items-center gap-4">
          <span className="size-tap-target shrink-0" />
          <span className="h-progress flex-1 rounded-full bg-hairline" />
          <span className="hidden min-h-button w-24 rounded-button border border-outline bg-surface lg:block" />
        </div>
        <div className="mx-auto flex w-full max-w-study flex-col gap-3 pt-6">
          <div className="grid min-h-52 grid-cols-[1fr_auto_1fr] rounded-card bg-surface shadow-raised lg:min-h-75">
            <span className="flex items-center justify-center p-6">
              <SkeletonLine text="text-question" width="w-1/2" />
            </span>
            <span className="my-7 w-px bg-hairline" />
            <span className="flex items-center justify-center p-6">
              <SkeletonLine text="text-answer" width="w-1/3" />
            </span>
          </div>
          <div className="flex gap-3">
            <span className="min-h-cta flex-1 rounded-button bg-tint-red" />
            <span className="min-h-cta flex-1 rounded-button bg-tint-green" />
          </div>
        </div>
      </Skeleton>
    </main>
  );
}
