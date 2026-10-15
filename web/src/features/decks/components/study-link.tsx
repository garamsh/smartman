import { Play } from "lucide-react";
import Link from "next/link";

const look =
  "flex min-h-cta items-center justify-center gap-2 rounded-button bg-ink px-6 text-label text-on-primary focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-ink";

/**
 * The primary button that opens a study session over [decks], named [label]; disabled when the
 * session would have no card to study.
 */
export function StudyLink({
  decks,
  cards,
  label,
}: {
  decks: readonly string[];
  cards: number;
  label: string;
}) {
  const content = (
    <>
      <Play aria-hidden className="size-small-icon" strokeWidth={2} />
      {label}
    </>
  );
  if (cards === 0) {
    return (
      <button type="button" disabled className={`${look} opacity-50`}>
        {content}
      </button>
    );
  }
  return (
    <Link href={`/study?decks=${decks.map(encodeURIComponent).join(",")}`} className={look}>
      {content}
    </Link>
  );
}
