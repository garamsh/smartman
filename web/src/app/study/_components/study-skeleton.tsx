import { Skeleton, SkeletonLine } from "@/components/skeleton";

/**
 * The study page while its cards are read: the header with the progress bar, the current card
 * and the three answer buttons, in their sizes.
 */
export function StudySkeleton() {
  return (
    <main className="mx-auto w-full max-w-study px-gutter py-6">
      <Skeleton status="카드를 불러오는 중이에요." className="flex flex-col gap-4">
        <div className="flex items-center gap-4">
          <span className="size-tap-target shrink-0" />
          <span className="h-progress flex-1 rounded-full bg-hairline" />
          <span className="min-h-button w-24 rounded-button border border-outline bg-surface" />
        </div>
        <div className="grid min-h-52 grid-cols-1 rounded-card bg-surface shadow-raised sm:grid-cols-[1fr_auto_1fr]">
          <span className="flex items-center justify-center p-6">
            <SkeletonLine text="text-question" width="w-1/2" />
          </span>
          <span className="mx-7 h-px bg-hairline sm:mx-0 sm:my-7 sm:h-auto sm:w-px" />
          <span className="flex items-center justify-center p-6">
            <SkeletonLine text="text-answer" width="w-1/3" />
          </span>
        </div>
        <div className="grid grid-cols-3 gap-3">
          {[0, 1, 2].map((button) => (
            <span
              key={button}
              className="min-h-button rounded-button border border-outline bg-surface"
            />
          ))}
        </div>
      </Skeleton>
    </main>
  );
}
