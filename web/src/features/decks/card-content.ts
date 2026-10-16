/**
 * One block of a card side, as the phone stores it: a `{type, payload}` object in the side's
 * JSON array (`deck.md`). Only text exists now; a block of another type is shown as a
 * placeholder naming it, so a card a later version wrote is shown, not lost.
 */
export type Content = { kind: "text"; text: string } | { kind: "unsupported"; type: string };

/**
 * The blocks of a stored card side, or null when [value] is not an array of blocks each with
 * a string `type`, and a string `payload.text` for a text block.
 */
export function parseContent(value: unknown): Content[] | null {
  if (!Array.isArray(value)) return null;
  const blocks: Content[] = [];
  for (const block of value as unknown[]) {
    if (typeof block !== "object" || block === null) return null;
    const type = "type" in block ? block.type : null;
    const payload = "payload" in block ? block.payload : null;
    if (typeof type !== "string") return null;
    if (type !== "text") {
      blocks.push({ kind: "unsupported", type });
      continue;
    }
    const text =
      typeof payload === "object" && payload !== null && "text" in payload ? payload.text : null;
    if (typeof text !== "string") return null;
    blocks.push({ kind: "text", text });
  }
  return blocks;
}

/** The one line of text a card side shows, its blocks joined by spaces, as on the phone. */
export function describeContent(blocks: Content[]): string {
  return blocks
    .map((block) => {
      switch (block.kind) {
        case "text":
          return block.text;
        case "unsupported":
          return `[이 버전에서 표시할 수 없는 내용: ${block.type}]`;
      }
    })
    .join(" ");
}
