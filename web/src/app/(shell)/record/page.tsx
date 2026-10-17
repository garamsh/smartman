import type { Metadata } from "next";

export const metadata: Metadata = { title: "기록 · smartman" };

/** 기록: the heading alone until #91's Part B fills the page. */
export default function RecordPage() {
  return <h1 className="text-display">기록</h1>;
}
