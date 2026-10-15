import type { Metadata } from "next";

import { ComingSoon } from "@/components/coming-soon";
import { legalDocuments } from "@/components/legal-links";

export const metadata: Metadata = { title: "이용약관 · smartman" };

/** The terms of service, or, until they are published, that they are coming. */
export default function TermsPage() {
  const [terms] = legalDocuments;
  return <ComingSoon title={terms.title} url={terms.url} />;
}
