/** The two legal documents, each by its name and the page of this app that publishes it. */
const legalDocuments = [
  { title: "이용약관", path: "/terms" },
  { title: "개인정보 처리방침", path: "/privacy" },
] as const;

/** Links to the terms of service and the privacy policy, each on its page of this app. */
export function LegalLinks() {
  return (
    <nav aria-label="약관" className="flex flex-wrap justify-center gap-2">
      {legalDocuments.map(({ title, path }) => (
        <a
          key={path}
          href={path}
          className="flex min-h-tap-target items-center px-2 text-caption font-semibold text-ink-2 underline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-ink"
        >
          {title}
        </a>
      ))}
    </nav>
  );
}
