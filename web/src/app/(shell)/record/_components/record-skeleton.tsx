import { Skeleton, SkeletonLine } from "@/design/skeleton";

/** The 기록 page while its record is read: the selector and the four charts' cards, in their sizes. */
export function RecordSkeleton() {
  return (
    <Skeleton status="기록을 불러오는 중이에요." className="flex flex-col gap-3">
      <span className="min-h-13 w-60 rounded-field bg-hairline" />
      <div className="grid gap-3 lg:grid-cols-2">
        {["lg:col-span-2 h-80", "h-40", "h-40", "lg:col-span-2 h-72"].map((size) => (
          <div key={size} className={`flex flex-col gap-3 rounded-previous bg-surface p-4 ${size}`}>
            <SkeletonLine text="text-label" width="w-2/5" />
          </div>
        ))}
      </div>
    </Skeleton>
  );
}
