import type { Metadata } from "next";

import { ComingSoon } from "@/components/coming-soon";
import { legalDocuments } from "@/components/legal-links";

export const metadata: Metadata = { title: "개인정보 처리방침 · smartman" };

/** The privacy policy, or, until it is published, that it is coming. */
export default function PrivacyPage() {
  const [, privacy] = legalDocuments;
  return <ComingSoon title={privacy.title} url={privacy.url} />;
}
