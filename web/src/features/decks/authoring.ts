import { v7 } from "uuid";

import {
  type Content,
  describeContent,
  frameVersions,
  isEarlier,
  isFramed,
  parseCardContent,
  parseContent,
  partsOfSpeech,
  plainText,
  type SenseLabel,
} from "./card-content";

/** Stored blocks accepted by the authoring boundary. */
export type Block = { type: string; v: number; id: string; payload: Record<string, unknown> };
/** A new card keeps its id across retries. */
export type CardDraft = { id: string; front: Block[]; back: Block[] };
/** A vocabulary meaning in the editor. */
export type Meaning = { labels: SenseLabel[]; meaning: string; examples: string[] };
/** The columns of a card a merge reads and writes, as they are stored. */
export type StoredCard = {
  front: unknown;
  back: unknown;
  template: unknown;
  templateVersion: unknown;
};

/** The phone's NFKC, whitespace and lowercase duplicate key. */
export function cardKey(front: Content[]): string {
  return describeContent(front).normalize("NFKC").trim().replace(/\s+/gu, " ").toLowerCase();
}
/**
 * Whether a line of [side] holds [back] under the card key normalization, as the phone's
 * `mergeBack`, or each of [back]'s lines is held, as a back of several lines is once merged, so a
 * retried save does not append it again.
 */
export function holdsBack(side: Content[], back: string): boolean {
  const key = (text: string) => cardKey([{ kind: "text", text }]);
  const lines = new Set(plainText(side).split("\n").map(key));
  return lines.has(key(back)) || back.split("\n").every((line) => lines.has(key(line)));
}
/**
 * [stored] with [back] merged in, as the phone's `addCards` merges a duplicate, its other blocks
 * as stored: a 칸 list takes a 글 of a back alone; two sides take a text block on the back and
 * record `free` version 1, a later build's template kept. [stored] itself when there is nothing
 * to merge, and null when it cannot be read.
 */
export function mergeBack(stored: StoredCard, back: string): StoredCard | null {
  const framed = isFramed(stored.template, stored.templateVersion);
  const read = parseCardContent(stored);
  const side = framed ? read?.back : parseContent(stored.back);
  if (!read || !side) return null;
  if (back.trim() === "" || holdsBack(side, back)) return stored;
  if (framed) {
    const payload = { front: "", back };
    const cell = { type: "text", v: frameVersions.get("text"), id: v7(), payload };
    return { ...stored, front: [...(stored.front as unknown[]), cell] };
  }
  return {
    ...stored,
    back: [...(stored.back as unknown[]), block("text", { text: back })],
    ...(isEarlier(stored.template, stored.templateVersion)
      ? { template: "free", templateVersion: 1 }
      : {}),
  };
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
