import { v7 } from "uuid";
import { field } from "@/supabase/row";
import { block, type CardDraft, textBlocks } from "./authoring";
import { describeContent, parseContent } from "./card-content";

/**
 * A photo's reviewed candidate retains its structured content until an explicit save: its front
 * and back as word to meaning, which its section's form turns (`section-form.ts`), the id of the
 * reversed card "양쪽 방향" adds, and the pronunciation and extras the form may show.
 */
export type Candidate = CardDraft & {
  topic: string;
  kind: "vocabulary" | "note";
  identify: boolean;
  pronunciation: string | null;
  extras: Extra[];
  reverseId: string;
  selected: boolean;
};
/** A note the page prints for a whole entry, such as a synonym, as the phone's `Extra`. */
export type Extra = { label: string; text: string };
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
    const spoken = field(card, "pronunciation") ?? null;
    const pronunciation = spoken === null ? null : isText(spoken) ? spoken.trim() : undefined;
    const extras = parseExtras(field(card, "extras"));
    if (pronunciation === undefined || !extras) return null;
    // An identify card starts left out, as the phone's `isIncluded`.
    result.push({
      id: v7(),
      topic,
      kind,
      identify: type === "identify",
      pronunciation,
      extras,
      reverseId: v7(),
      front: frontBlocks,
      back,
      selected: type !== "identify",
    });
  }
  return result;
}

function isText(value: unknown): value is string {
  return typeof value === "string" && value.trim() !== "";
}

/** A card's extras, each a non-empty label and text, trimmed, as the phone's `_parseExtra`; null otherwise. */
function parseExtras(value: unknown): Extra[] | null {
  if (value === undefined || value === null) return [];
  if (!Array.isArray(value)) return null;
  const extras: Extra[] = [];
  for (const extra of value) {
    const label = field(extra, "label");
    const text = field(extra, "text");
    if (!isText(label) || !isText(text)) return null;
    extras.push({ label: label.trim(), text: text.trim() });
  }
  return extras;
}
