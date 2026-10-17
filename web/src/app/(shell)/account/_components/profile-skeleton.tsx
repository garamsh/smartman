import { Skeleton, SkeletonLine } from "@/design/skeleton";

/**
 * The account page while the session is read: the profile card, the theme choice and the
 * sign-out row, in their sizes.
 */
export function ProfileSkeleton() {
  return (
    <Skeleton status="계정을 불러오는 중이에요." className="flex flex-col gap-section-gap">
      <div className="flex items-center gap-4 rounded-card bg-surface p-5">
        <span className="size-avatar shrink-0 rounded-full bg-hairline" />
        <SkeletonLine text="text-body-strong" width="w-1/2" />
      </div>
      <div className="flex flex-col gap-3">
        <SkeletonLine text="text-section" width="w-10" />
        <div className="rounded-row bg-surface p-1.5">
          <div className="grid grid-cols-3 gap-1 rounded-field bg-ground p-1">
            {[0, 1, 2].map((choice) => (
              <span key={choice} className="min-h-tap-target" />
            ))}
          </div>
        </div>
      </div>
      <div className="flex flex-col gap-3">
        <SkeletonLine text="text-section" width="w-10" />
        <span className="min-h-button rounded-row bg-surface" />
      </div>
    </Skeleton>
  );
}
