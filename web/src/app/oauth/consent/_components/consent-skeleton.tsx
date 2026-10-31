import { Skeleton, SkeletonLine } from "@/design/skeleton";

/** The consent page while the request is read: its title and the one group of three rows. */
export function ConsentSkeleton() {
  return (
    <Skeleton status="연결 요청을 불러오는 중이에요." className="flex flex-col gap-section-gap">
      <SkeletonLine text="text-display" width="w-2/3" />
      <div className="flex flex-col divide-y divide-hairline rounded-group bg-surface">
        {[0, 1, 2].map((row) => (
          <span key={row} className="flex flex-col gap-1 px-4 py-3">
            <SkeletonLine text="text-caption" width="w-10" />
            <SkeletonLine text="text-body" width="w-1/2" />
          </span>
        ))}
      </div>
    </Skeleton>
  );
}
