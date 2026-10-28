/**
 * A card's content as the web's direct entry writes it and as the read tools describe it:
 * the blocks, the duplicate key, the labels and the ids (web-decks.md §Authoring, ADR 0114).
 */

/** A stored block, as the phone and the web write it (ADR 0106). */
export type Block = {
  readonly type: "text" | "senses";
  readonly v: 1;
  readonly id: string;
  readonly payload: Record<string, unknown>;
};

/** Each part of speech a label may name, by the short form a card shows it as. */
const PARTS_OF_SPEECH: Record<string, string> = {
  "명": "noun",
  "동": "verb",
  "형": "adjective",
  "부": "adverb",
  "대": "pronoun",
  "전": "preposition",
  "접": "conjunction",
  "감": "interjection",
  "관": "determiner",
  "수": "numeral",
  "조": "particle",
  "조동": "auxiliary",
  "양": "classifier",
  "구": "phrase",
};

/** The short forms a label may take to be stored as a part of speech, for the tools' text. */
export const PART_OF_SPEECH_FORMS = Object.keys(PARTS_OF_SPEECH);

/** A sense's label as stored: a part of speech by its short form, or any other label. */
export type Label =
  | {
    readonly kind: "part_of_speech";
    readonly category: string;
    readonly text: string;
  }
  | { readonly kind: "other"; readonly category: null; readonly text: string };

/** Each word of [texts] as a label, a short part-of-speech form as that part of speech. */
export function labelsOf(texts: readonly string[]): Label[] {
  return texts.flatMap((text) => text.trim().split(/\s+/u)).filter((text) =>
    text !== ""
  )
    .map((text): Label => {
      const category = PARTS_OF_SPEECH[text];
      return category === undefined
        ? { kind: "other", category: null, text }
        : { kind: "part_of_speech", category, text };
    });
}

/** The phone's duplicate key: the front's text in NFKC, its whitespace collapsed, lowercased. */
export function cardKey(front: string): string {
  return front.normalize("NFKC").trim().replace(/\s+/gu, " ").toLowerCase();
}

/** Makes a version 7 uuid from a clock and a random source, as the phone and the web do. */
export type IdSource = {
  readonly now: () => number;
  readonly random: (bytes: number) => Uint8Array;
};

/** A version 7 uuid: 48 bits of [ids]' milliseconds, then its random bits with the version and variant. */
export function uuidV7(ids: IdSource): string {
  const bytes = new Uint8Array(16);
  let time = ids.now();
  for (let index = 5; index >= 0; index--) {
    bytes[index] = time % 256;
    time = Math.floor(time / 256);
  }
  bytes.set(ids.random(10), 6);
  bytes[6] = (bytes[6] & 0x0f) | 0x70;
  bytes[8] = (bytes[8] & 0x3f) | 0x80;
  const hex = [...bytes].map((byte) => byte.toString(16).padStart(2, "0")).join(
    "",
  );
  return `${hex.slice(0, 8)}-${hex.slice(8, 12)}-${hex.slice(12, 16)}-${
    hex.slice(16, 20)
  }-${hex.slice(20)}`;
}

/**
 * The two sides direct entry writes: the front as a text block; the back as a text block, or, with
 * a label or an example, as a senses block of one sense.
 */
export function sides(
  card: {
    front: string;
    back: string;
    labels: readonly Label[];
    examples: readonly string[];
  },
  ids: IdSource,
): { front: Block[]; back: Block[] } {
  const front: Block[] = [{
    type: "text",
    v: 1,
    id: uuidV7(ids),
    payload: { text: card.front },
  }];
  const back: Block[] = card.labels.length === 0 && card.examples.length === 0
    ? [{ type: "text", v: 1, id: uuidV7(ids), payload: { text: card.back } }]
    : [{
      type: "senses",
      v: 1,
      id: uuidV7(ids),
      payload: {
        senses: [{
          labels: card.labels,
          meaning: card.back,
          examples: card.examples,
        }],
      },
    }];
  return { front, back };
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

function strings(value: unknown): string[] {
  return Array.isArray(value)
    ? value.filter((item) => typeof item === "string")
    : [];
}

/** A sense's line: each label in brackets, by its short form, then the meaning. */
function senseLine(sense: unknown): string {
  if (!isRecord(sense)) return "";
  const labels = Array.isArray(sense.labels) ? sense.labels : [];
  const shown = labels.flatMap((label) => {
    if (!isRecord(label) || typeof label.text !== "string") return [];
    const short = label.kind === "part_of_speech"
      ? PART_OF_SPEECH_FORMS.find((form) =>
        PARTS_OF_SPEECH[form] === label.category
      )
      : undefined;
    return [`[${short ?? label.text}]`];
  });
  const meaning = typeof sense.meaning === "string" ? sense.meaning : "";
  const examples = strings(sense.examples).map((example) => `\n  - ${example}`)
    .join("");
  return [...shown, meaning].join(" ") + examples;
}

/** A cloze's text with each blank filled by its answer. */
function filledCloze(payload: Record<string, unknown>): string {
  const text = typeof payload.text === "string" ? payload.text : "";
  const answers = strings(payload.answers);
  return text.split("___").map((part, index) =>
    part + (index < text.split("___").length - 1 ? answers[index] ?? "" : "")
  ).join("");
}

/**
 * A stored side as one text, its blocks joined by spaces, as the web describes it: a cloze filled,
 * a table row by row, each sense a line with its examples, a photo "[photo]" and a sound "[sound]".
 * A block this function does not know reads as "[<type>]". The stored row is read, never written.
 */
export function sideText(blocks: unknown): string {
  if (!Array.isArray(blocks)) return "";
  return blocks.map((block) => {
    if (!isRecord(block) || typeof block.type !== "string") return "";
    const payload = isRecord(block.payload) ? block.payload : {};
    switch (block.type) {
      case "text":
        return typeof payload.text === "string" ? payload.text : "";
      case "cloze":
        return filledCloze(payload);
      case "table": {
        const rows = [
          payload.columns,
          ...(Array.isArray(payload.rows) ? payload.rows : []),
        ];
        return rows.map((row) => strings(row).join(" | ")).join("\n");
      }
      case "senses":
        return (Array.isArray(payload.senses) ? payload.senses : []).map(
          senseLine,
        ).join("\n");
      case "image":
        return "[photo]";
      case "audio":
        return "[sound]";
      default:
        return `[${block.type}]`;
    }
  }).join(" ");
}

/**
 * Whether a card with [front] is drawn whole, its back never shown: a cloze, a table, or a photo
 * with a box over it (ADR 0109).
 */
export function isWholeCard(front: unknown): boolean {
  return Array.isArray(front) &&
    front.some((block) =>
      isRecord(block) && (block.type === "cloze" || block.type === "table" ||
        (block.type === "image" && isRecord(block.payload) &&
          Array.isArray(block.payload.boxes) && block.payload.boxes.length > 0))
    );
}
