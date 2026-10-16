import { Play } from "lucide-react";
import Link from "next/link";

const look =
  "flex min-h-cta items-center justify-center gap-2 rounded-button bg-ink px-6 text-label text-on-primary focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-ink";

/**
 * The primary button that opens a study session over [decks], named [label]; with no card left
 * today the session opens on the completion card or on nothing to study.
 */
export function StudyLink({ decks, label }: { decks: readonly string[]; label: string }) {
  return (
    <Link href={`/study?decks=${decks.map(encodeURIComponent).join(",")}`} className={look}>
      <Play aria-hidden className="size-small-icon" strokeWidth={2} />
      {label}
    </Link>
  );
}
