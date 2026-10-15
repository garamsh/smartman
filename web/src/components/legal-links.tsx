import { env } from "@/env";

/** The two legal documents: each one's name, the page that stands in for it, and its link. */
export const legalDocuments = [
  { title: "이용약관", path: "/terms", url: env.termsUrl },
  { title: "개인정보 처리방침", path: "/privacy", url: env.privacyUrl },
] as const;

/**
 * Links to the terms of service and the privacy policy: each to its document once it is
 * published, and until then to the page that says it is coming.
 */
export function LegalLinks() {
  return (
    <nav aria-label="약관" className="flex flex-wrap justify-center gap-2">
      {legalDocuments.map(({ title, path, url }) => (
        <a
          key={path}
          href={url ?? path}
          className="flex min-h-11 items-center px-2 text-caption font-semibold text-ink-2 underline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-ink"
        >
          {title}
        </a>
      ))}
    </nav>
  );
}
