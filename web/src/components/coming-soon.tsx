import Link from "next/link";
import { redirect } from "next/navigation";

import { Mascot } from "./brand";

/**
 * The page for a document titled [title]: its published [url] once there is one, and until
 * then a page that says it is coming.
 */
export function ComingSoon({ title, url }: { title: string; url: string | null }) {
  if (url !== null) redirect(url);
  return (
    <main className="mx-auto flex min-h-dvh w-full max-w-list flex-col items-center justify-center gap-4 px-5 py-8 text-center">
      <Mascot className="size-28 bg-brand-tint" />
      <h1 className="text-title">{title}</h1>
      <p className="text-body text-muted">아직 준비 중이에요. 곧 열어 드릴게요.</p>
      <Link
        href="/"
        className="flex min-h-11 items-center px-2 text-label text-ink-2 underline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-ink"
      >
        처음으로
      </Link>
    </main>
  );
}
