import Link from "next/link";

const look =
  "flex min-h-13 items-center justify-center rounded-row bg-know px-6 font-semibold text-on-know focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-ink";

/**
 * The button that opens a study session over [decks], named [label]; disabled when the
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
  if (cards === 0) {
    return (
      <button type="button" disabled className={`${look} opacity-50`}>
        {label}
      </button>
    );
  }
  return (
    <Link href={`/study?decks=${decks.map(encodeURIComponent).join(",")}`} className={look}>
      {label}
    </Link>
  );
}
