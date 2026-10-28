import { v7 } from "uuid";
import { field } from "@/supabase/row";
import { block, type CardDraft, textBlocks } from "./authoring";
import { describeContent, parseContent } from "./card-content";

/** A photo's reviewed candidate retains its structured content until an explicit save. */
export type Candidate = CardDraft & {
  topic: string;
  kind: "vocabulary" | "note";
  selected: boolean;
};
/** Parses the function's current response and maps its fields as the phone does. */
export function parseCandidates(body: unknown): Candidate[] | null {
  const cards = field(body, "cards");
  if (!Array.isArray(cards) || cards.length < 1 || cards.length > 100) return null;
  const result: Candidate[] = [];
  for (const raw of cards) {
    const card: unknown = raw;
    const front = field(card, "front");
    const answer = field(card, "answer");
    const topic = field(card, "topic");
    const kind = field(card, "kind");
    const type = field(card, "type");
    if (
      typeof front !== "string" ||
      !front.trim() ||
      Array.from(front).length > 500 ||
      typeof topic !== "string" ||
      Array.from(topic).length > 60 ||
      (kind !== "vocabulary" && kind !== "note")
    )
      return null;
    let frontBlocks = textBlocks(front);
    let back = typeof answer === "string" ? textBlocks(answer) : [];
    if (kind === "vocabulary") {
      if (type !== "concept") return null;
      back = [block("senses", { senses: field(card, "senses") })];
    } else if (type === "cloze") {
      const cloze = field(card, "cloze");
      frontBlocks = [block("cloze", { text: front, answers: field(cloze, "answers") })];
    } else if (type === "table") {
      const table = field(card, "table");
      frontBlocks.push(
        block("table", {
          columns: field(table, "columns"),
          rows: field(table, "rows"),
          blanks: field(table, "blanks"),
          spans: [],
        }),
      );
    } else if (type !== "concept" && type !== "identify") return null;
    const parsed = parseContent(frontBlocks);
    if (!parsed) return null;
    if (type === "cloze" || type === "table") back = textBlocks(describeContent(parsed));
    if (!parseContent(back) || back.length === 0) return null;
    result.push({ id: v7(), topic, kind, front: frontBlocks, back, selected: true });
  }
  return result;
}
