import { Skeleton, SkeletonLine } from "@/design/skeleton";

/** An admin page's placeholder: three rows of the lists every admin page shows. */
export function AdminSkeleton() {
  return (
    <Skeleton status="불러오는 중이에요." className="flex flex-col gap-row-gap">
      {[0, 1, 2].map((row) => (
        <div key={row} className="flex flex-col gap-2 rounded-row bg-surface p-4">
          <SkeletonLine text="text-body-strong" width="w-40" />
          <SkeletonLine text="text-caption" width="w-64" />
        </div>
      ))}
    </Skeleton>
  );
}
