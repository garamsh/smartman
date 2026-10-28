import { v7 } from "uuid";

import {
  type Content,
  describeContent,
  parseContent,
  partsOfSpeech,
  type SenseLabel,
} from "./card-content";

/** Stored blocks accepted by the authoring boundary. */
export type Block = { type: string; v: number; id: string; payload: Record<string, unknown> };
/** A new card keeps its id across retries. */
export type CardDraft = { id: string; front: Block[]; back: Block[] };
/** A vocabulary meaning in the editor. */
export type Meaning = { labels: SenseLabel[]; meaning: string; examples: string[] };

/** The phone's NFKC, whitespace and lowercase duplicate key. */
export function cardKey(front: Content[]): string {
  return describeContent(front).normalize("NFKC").trim().replace(/\s+/gu, " ").toLowerCase();
}
/** A block at the version the phone writes. */
export function block(type: string, payload: Record<string, unknown>): Block {
  return { type, v: type === "table" ? 2 : 1, id: v7(), payload };
}
/** Plain text stored as a block, with empty text omitted. */
export function textBlocks(text: string): Block[] {
  return text.trim() ? [block("text", { text: text.trim() })] : [];
}
/** Typed labels, with the phone's short part-of-speech forms. */
export function labelsFromText(text: string): SenseLabel[] {
  return text
    .trim()
    .split(/\s+/u)
    .filter(Boolean)
    .map((text): SenseLabel => {
      for (const [category, short] of Object.entries(partsOfSpeech)) {
        if (short === text && category in partsOfSpeech) {
          const entry = Object.keys(partsOfSpeech).find(
            (key): key is keyof typeof partsOfSpeech => key === category,
          );
          if (entry) return { kind: "part_of_speech", category: entry, text };
        }
      }
      return { kind: "other", category: null, text };
    });
}
/** A wire-format card with bounded, readable blocks; unsupported blocks are never rewritten. */
export function parseDraft(value: unknown): CardDraft | null {
  if (
    !value ||
    typeof value !== "object" ||
    !("id" in value) ||
    typeof value.id !== "string" ||
    !("front" in value) ||
    !("back" in value)
  )
    return null;
  const front = parseBlocks(value.front);
  const back = parseBlocks(value.back);
  if (!front || !back || front.length === 0) return null;
  const read = parseContent(front);
  return read && cardKey(read) ? { id: value.id, front, back } : null;
}
function parseBlocks(value: unknown): Block[] | null {
  if (!Array.isArray(value) || value.length > 100) return null;
  const result: Block[] = [];
  for (const raw of value) {
    const item: unknown = raw;
    if (
      !item ||
      typeof item !== "object" ||
      !("type" in item) ||
      typeof item.type !== "string" ||
      !("v" in item) ||
      typeof item.v !== "number" ||
      !("id" in item) ||
      typeof item.id !== "string" ||
      !("payload" in item) ||
      !item.payload ||
      typeof item.payload !== "object" ||
      Array.isArray(item.payload)
    )
      return null;
    const read = parseContent([item]);
    if (
      !read ||
      read.some(
        (content) =>
          content.kind === "unsupported" || content.kind === "image" || content.kind === "audio",
      )
    )
      return null;
    const payload: Record<string, unknown> = Object.fromEntries(Object.entries(item.payload));
    result.push({ type: item.type, v: item.v, id: item.id, payload });
  }
  return result;
}
