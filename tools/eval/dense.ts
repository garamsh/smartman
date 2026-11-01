/**
 * The ways of reading a dense page whole that the eval measures against the function's own call
 * (ADR 0135): a leaner reply shape, a higher output cap, and one call continuing after a cut reply.
 * None is deployed; the PM's paid run chooses which, if any, the function takes.
 */

import {
  CARD_RULES,
  cardsSchema,
  MAX_CARDS,
  OUTPUT_CONTRACT,
  type ParsedReply,
  parseReply,
} from "../../supabase/functions/extract-cards/cards.ts";
import { RETRY_START_LIMIT_MS } from "../../supabase/functions/extract-cards/handler.ts";
import {
  CARD_LIST,
  extractCards,
  type ExtractDeps,
  type Extraction,
  MAX_OUTPUT_TOKENS,
  type ModelId,
  type ReplyForm,
} from "../../supabase/functions/extract-cards/openrouter.ts";
import type {
  Image,
  LanguageHints,
} from "../../supabase/functions/extract-cards/request.ts";
import { normalize } from "./metrics.ts";

/** One way of reading a photo: its label, the most calls and reply tokens an image may take. */
export type Alternative = {
  readonly label: string;
  readonly calls: 1 | 2;
  readonly maxTokens: number;
  readonly extract: (
    image: Image,
    languages: LanguageHints,
    model: ModelId,
    prompt: string,
    deps: ExtractDeps,
  ) => Promise<Extraction>;
};

const card = cardsSchema.properties.cards.items;
const sense = card.properties.senses.items;

/**
 * The card list's schema with every field a card may leave empty optional: only `kind`, `front`
 * and `topic` are required on a card, and only `meaning` on a sense.
 */
export const leanSchema = {
  ...cardsSchema,
  properties: {
    cards: {
      ...cardsSchema.properties.cards,
      items: {
        ...card,
        properties: {
          ...card.properties,
          senses: {
            ...card.properties.senses,
            items: { ...sense, required: ["meaning"] },
          },
        },
        required: ["kind", "front", "topic"],
      },
    },
  },
};

/** The rule that replaces `CARD_RULES.fields` in the lean contract. */
export const LEAN_FIELDS_RULE =
  `A card holds only the fields above, each at most once, and leaves out every field it does not use: "type" when it is "concept", an "answer", "pronunciation", "table" or "cloze" that is null, and every empty list, a sense's empty "labels" and "examples" included.`;

/** The output contract with the lean rule for the fields a card leaves out. */
export const LEAN_CONTRACT = OUTPUT_CONTRACT
  .replace("Every card has these fields:", "A card may have these fields:")
  .replace(CARD_RULES.fields, LEAN_FIELDS_RULE);

/** What a field a lean card leaves out stands for. */
const CARD_DEFAULTS = {
  type: "concept",
  answer: null,
  senses: [],
  extras: [],
  pronunciation: null,
  examples: [],
  table: null,
  cloze: null,
};
const SENSE_DEFAULTS = { labels: [], examples: [] };

/**
 * A lean reply read by the card list's rules: each card's left-out fields filled with what they
 * stand for, then `parseReply`. Null when it is not JSON of `{cards: [...]}`.
 */
export function parseLeanReply(reply: string): ParsedReply | null {
  let value: unknown;
  try {
    value = JSON.parse(reply);
  } catch {
    return null;
  }
  if (!isRecord(value) || !Array.isArray(value.cards)) return null;
  const cards = value.cards.map((item: unknown) => {
    if (!isRecord(item)) return item;
    const filled: Record<string, unknown> = { ...CARD_DEFAULTS, ...item };
    if (Array.isArray(filled.senses)) {
      filled.senses = filled.senses.map((one: unknown) =>
        isRecord(one) ? { ...SENSE_DEFAULTS, ...one } : one
      );
    }
    return filled;
  });
  return parseReply(JSON.stringify({ ...value, cards }));
}

export const LEAN_LIST: ReplyForm = {
  schema: leanSchema,
  contract: LEAN_CONTRACT,
  parse: parseLeanReply,
  maxTokens: MAX_OUTPUT_TOKENS,
};

/**
 * The higher cap: the PM's probe of 2026-11-01 measured about 320 output tokens a second, so a reply
 * of 19,200 tokens ends at the 60 s model timeout; 18,000 leaves the prompt's reading about 4 s.
 */
export const HIGHER_CAP_TOKENS = 18_000;

/** The text asking for the entries after the one a cut reply ended at. */
export function continueAfter(front: string, read: number): string {
  return `A reply to this material was cut off at the output limit after ${read} cards, the last for "${front}". Answer with the cards of the entries that come after that entry only, in the material's order, and none for the ${read} entries up to it.`;
}

/**
 * The function's call, then, when its reply was cut and it ended before the retry limit, one more
 * call asking for the entries after the last card read, as the one retry a photo may make. The
 * second reply's cards whose front a first card has are left out, and the list is cut at
 * `MAX_CARDS`; when the second call keeps no card, the first call's cards are the answer.
 */
export async function extractContinuing(
  image: Image,
  languages: LanguageHints,
  model: ModelId,
  prompt: string,
  deps: ExtractDeps,
): Promise<Extraction> {
  const first = await extractCards(image, languages, model, prompt, deps);
  if (
    first.kind !== "cards" || !first.cut ||
    first.attempts[0].latencyMs >= RETRY_START_LIMIT_MS
  ) return first;
  const last = first.cards[first.cards.length - 1];
  const second = await extractCards(image, languages, model, prompt, deps, {
    followUp: continueAfter(last.front, first.cards.length),
  });
  const attempts = [...first.attempts, ...second.attempts];
  if (second.kind !== "cards") return { ...first, attempts };
  const read = new Set(first.cards.map((one) => normalize(one.front)));
  const added = second.cards.filter((one) => !read.has(normalize(one.front)));
  return {
    kind: "cards",
    cards: [...first.cards, ...added].slice(0, MAX_CARDS),
    dropped: [...first.dropped, ...second.dropped],
    cut: second.cut,
    attempts,
  };
}

/** The function's own call, and the three ways `--alternatives` may name beside it. */
export const ALTERNATIVES: readonly Alternative[] = [
  {
    label: "today",
    calls: 1,
    maxTokens: MAX_OUTPUT_TOKENS,
    extract: (image, languages, model, prompt, deps) =>
      extractCards(image, languages, model, prompt, deps),
  },
  {
    label: "lean",
    calls: 1,
    maxTokens: MAX_OUTPUT_TOKENS,
    extract: (image, languages, model, prompt, deps) =>
      extractCards(image, languages, model, prompt, deps, { form: LEAN_LIST }),
  },
  {
    label: "cap",
    calls: 1,
    maxTokens: HIGHER_CAP_TOKENS,
    extract: (image, languages, model, prompt, deps) =>
      extractCards(image, languages, model, prompt, deps, {
        form: { ...CARD_LIST, maxTokens: HIGHER_CAP_TOKENS },
      }),
  },
  {
    label: "continue",
    calls: 2,
    maxTokens: MAX_OUTPUT_TOKENS,
    extract: extractContinuing,
  },
];

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}
