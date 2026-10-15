"use client";

/** What a page shows when rendering it failed unexpectedly. */
export default function ErrorPage({
  reset,
}: {
  error: Error & { digest?: string };
  reset: () => void;
}) {
  return (
    <main className="mx-auto flex min-h-dvh w-full max-w-sm flex-col justify-center gap-6 px-6">
      <h1 className="text-2xl font-bold">문제가 생겼어요</h1>
      <p className="text-muted">잠시 후 다시 시도해 주세요.</p>
      <button
        type="button"
        onClick={reset}
        className="min-h-button rounded-row bg-ink px-6 font-semibold text-surface focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-ink"
      >
        다시 시도
      </button>
    </main>
  );
}
