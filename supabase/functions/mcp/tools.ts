/**
 * The five tools a model calls: their definitions, written for a model that has no other
 * documentation, and their calls, each answering a result or a refusal the model can act on.
 */

import { SupabaseError } from "../_shared/auth.ts";
import {
  cardKey,
  type IdSource,
  PART_OF_SPEECH_FORMS,
  uuidV7,
} from "./cards.ts";
import { blocksOut, cellsOf, searchText, type StoredSides } from "./frame.ts";
import { GUIDE_URI } from "./guide.ts";
import {
  MAX_BLOCKS,
  MAX_EXAMPLES,
  MAX_LABELS,
  MAX_SENSES,
  MAX_TEXT,
  type ReadCard,
  readCard,
  type StoredBlock,
} from "./input.ts";
import { fetchPhoto, MAX_PHOTO_BYTES, type PhotoDeps } from "./photo.ts";
import {
  allCards,
  deckKeys,
  insert,
  listCards,
  listDecks,
  readDeck,
  type Store,
  storePhoto,
} from "./store.ts";

/** The most cards one `add_cards` call takes. */
export const MAX_CARDS = 100;
/** The most photos one call fetches, so a call stays under the platform's wall clock. */
export const MAX_PHOTOS = 10;
/** The longest a deck's name may be, as on the web. */
const MAX_NAME = 500;

/** A tool's answer: its structured result, or a refusal in words the model can act on. */
export type ToolResult =
  | { readonly kind: "result"; readonly value: Record<string, unknown> }
  | { readonly kind: "refused"; readonly message: string };

const refuse = (message: string): ToolResult => ({ kind: "refused", message });
const result = (value: Record<string, unknown>): ToolResult => ({
  kind: "result",
  value,
});

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/;

const deckId = {
  type: "string",
  format: "uuid",
  description: "The deck's id, as list_decks or create_deck returned it.",
};
const deckOut = {
  type: "object",
  properties: { id: { type: "string" }, name: { type: "string" } },
  required: ["id", "name"],
};
const labelsField = {
  type: "array",
  maxItems: MAX_LABELS,
  items: { type: "string" },
  description:
    `Labels shown in brackets before the meaning. A part of speech is one of these short forms: ${
      PART_OF_SPEECH_FORMS.join(", ")
    } (명 noun, 동 verb, 형 adjective, 부 adverb, 대 pronoun, 전 preposition, 접 conjunction, 감 interjection, 관 determiner, 수 numeral, 조 particle, 조동 auxiliary, 양 classifier, 구 phrase); any other text is stored as a label of its own.`,
};
const examplesField = {
  type: "array",
  maxItems: MAX_EXAMPLES,
  items: { type: "string" },
  description: "Example sentences for the meaning.",
};
const cellIndex = { type: "integer", minimum: 0 };
const fraction = { type: "number", minimum: 0, maximum: 1 };
const sideField = { type: "string", enum: ["front", "back"] };

/** The union on `type`, each variant saying when to use it. */
const blockIn = {
  anyOf: [
    {
      type: "object",
      description:
        'A question and its answer, or any text: front is shown first and back at the reveal; either may be left out, not both. {"type":"text","front":"Capital of France?","back":"Paris"}',
      properties: {
        type: { const: "text" },
        front: { type: "string", maxLength: MAX_TEXT },
        back: { type: "string", maxLength: MAX_TEXT },
      },
      required: ["type"],
      additionalProperties: false,
    },
    {
      type: "object",
      description:
        'A word and its meanings; ask names what is shown first. {"type":"senses","term":"apple","ask":"term","senses":[{"labels":["명"],"meaning":"사과","examples":[]}]}',
      properties: {
        type: { const: "senses" },
        term: { type: "string", maxLength: MAX_TEXT },
        ask: { type: "string", enum: ["term", "meaning"], default: "term" },
        senses: {
          type: "array",
          minItems: 1,
          maxItems: MAX_SENSES,
          items: {
            type: "object",
            properties: {
              labels: labelsField,
              meaning: { type: "string", minLength: 1, maxLength: MAX_TEXT },
              examples: examplesField,
            },
            required: ["meaning"],
            additionalProperties: false,
          },
        },
      },
      required: ["type", "term", "senses"],
      additionalProperties: false,
    },
    {
      type: "object",
      description:
        'A sentence to recall in context: one ___ for each answer, in order. Needs no back. {"type":"cloze","text":"The capital of France is ___.","answers":["Paris"]}',
      properties: {
        type: { const: "cloze" },
        text: { type: "string", maxLength: MAX_TEXT },
        answers: {
          type: "array",
          minItems: 1,
          items: { type: "string", minLength: 1, maxLength: MAX_TEXT },
        },
      },
      required: ["type", "text", "answers"],
      additionalProperties: false,
    },
    {
      type: "object",
      description:
        'A comparison or classification, its cells to recall as blanks, counted from 0 among the rows. Needs no back. {"type":"table","columns":["Organ","Job"],"rows":[["Heart","Pumps blood"]],"blanks":[{"row":0,"column":1}]}',
      properties: {
        type: { const: "table" },
        columns: {
          type: "array",
          minItems: 1,
          items: { type: "string", maxLength: MAX_TEXT },
        },
        rows: {
          type: "array",
          minItems: 1,
          items: {
            type: "array",
            items: { type: "string", maxLength: MAX_TEXT },
          },
        },
        blanks: {
          type: "array",
          description: "Whole cells to recall.",
          items: {
            type: "object",
            properties: { row: cellIndex, column: cellIndex },
            required: ["row", "column"],
            additionalProperties: false,
          },
        },
        spans: {
          type: "array",
          description:
            "Runs of a cell's text to recall, start and end in UTF-16 code units, in cells that are not blanks.",
          items: {
            type: "object",
            properties: {
              row: cellIndex,
              column: cellIndex,
              start: cellIndex,
              end: cellIndex,
            },
            required: ["row", "column", "start", "end"],
            additionalProperties: false,
          },
        },
      },
      required: ["type", "columns", "rows"],
      additionalProperties: false,
    },
    {
      type: "object",
      description:
        `A diagram or picture, fetched from a public https url: a JPEG, PNG or WebP file of at most ${MAX_PHOTO_BYTES} bytes. Give side while it has no boxes, or boxes to hide parts of it, and no side. {"type":"image","url":"https://example.com/heart.png","boxes":[{"x":0.1,"y":0.2,"w":0.3,"h":0.1,"answer":"aorta"}]}`,
      properties: {
        type: { const: "image" },
        url: { type: "string", format: "uri" },
        side: sideField,
        boxes: {
          type: "array",
          items: {
            type: "object",
            properties: {
              x: fraction,
              y: fraction,
              w: fraction,
              h: fraction,
              answer: { type: "string" },
            },
            required: ["x", "y", "w", "h"],
            additionalProperties: false,
          },
        },
      },
      required: ["type", "url"],
      additionalProperties: false,
    },
  ],
};

const cardOut = {
  type: "object",
  properties: {
    id: { type: "string" },
    blocks: {
      type: "array",
      description:
        "The card's blocks in add_cards' union, except that a photo names its stored media id, width and height in place of url, a sound is an audio block, and a block of a later version is an unknown block.",
      items: { type: "object", properties: { type: { type: "string" } } },
    },
  },
  required: ["id", "blocks"],
};

/** The tools as `tools/list` returns them. */
export const TOOLS = [
  {
    name: "list_decks",
    title: "List decks",
    description:
      "Lists the signed-in user's knowno flashcard decks, oldest first, each with its id, name and number of cards. Call it first to find the deck_id the other tools take.",
    inputSchema: {
      type: "object",
      properties: {},
      additionalProperties: false,
    },
    outputSchema: {
      type: "object",
      properties: {
        decks: {
          type: "array",
          items: {
            type: "object",
            properties: {
              id: { type: "string" },
              name: { type: "string" },
              card_count: { type: "integer" },
            },
            required: ["id", "name", "card_count"],
          },
        },
      },
      required: ["decks"],
    },
    annotations: { readOnlyHint: true, openWorldHint: false },
  },
  {
    name: "list_cards",
    title: "List cards in a deck",
    description:
      "Lists one deck's cards, oldest first, a page at a time. Each card has its blocks, in the form add_cards takes. To read the next page, call again with offset set to next_offset; next_offset is null on the last page.",
    inputSchema: {
      type: "object",
      properties: {
        deck_id: deckId,
        offset: {
          type: "integer",
          minimum: 0,
          default: 0,
          description: "How many cards to skip.",
        },
        limit: {
          type: "integer",
          minimum: 1,
          maximum: 100,
          default: 50,
          description: "How many cards to return, 1 to 100.",
        },
      },
      required: ["deck_id"],
      additionalProperties: false,
    },
    outputSchema: {
      type: "object",
      properties: {
        deck: deckOut,
        total: {
          type: "integer",
          description: "How many cards the deck holds.",
        },
        cards: { type: "array", items: cardOut },
        next_offset: {
          anyOf: [{ type: "integer" }, { type: "null" }],
          description: "The offset of the next page, or null on the last page.",
        },
      },
      required: ["deck", "total", "cards", "next_offset"],
    },
    annotations: { readOnlyHint: true, openWorldHint: false },
  },
  {
    name: "search_cards",
    title: "Search cards",
    description:
      "Finds the signed-in user's cards, across all their decks, whose text contains the query in any block, an answer included, ignoring case. Returns at most limit cards, each with its blocks and deck.",
    inputSchema: {
      type: "object",
      properties: {
        query: {
          type: "string",
          minLength: 1,
          maxLength: 200,
          description: "Text to find.",
        },
        limit: {
          type: "integer",
          minimum: 1,
          maximum: 100,
          default: 20,
          description: "How many cards to return at most, 1 to 100.",
        },
      },
      required: ["query"],
      additionalProperties: false,
    },
    outputSchema: {
      type: "object",
      properties: {
        cards: {
          type: "array",
          items: {
            ...cardOut,
            properties: { ...cardOut.properties, deck: deckOut },
            required: [...cardOut.required, "deck"],
          },
        },
        truncated: {
          type: "boolean",
          description: "True when more cards matched than were returned.",
        },
      },
      required: ["cards", "truncated"],
    },
    annotations: { readOnlyHint: true, openWorldHint: false },
  },
  {
    name: "create_deck",
    title: "Create a deck",
    description:
      "Creates a new, private, empty deck for the signed-in user and returns its id. It does not check for a deck of the same name: call list_decks first if the user may already have one. The deck appears on the user's phone and on the web at their next sync.",
    inputSchema: {
      type: "object",
      properties: {
        name: {
          type: "string",
          minLength: 1,
          maxLength: MAX_NAME,
          description: "The deck's name, as the user will see it.",
        },
      },
      required: ["name"],
      additionalProperties: false,
    },
    outputSchema: {
      type: "object",
      properties: { deck: deckOut },
      required: ["deck"],
    },
    annotations: {
      readOnlyHint: false,
      destructiveHint: false,
      openWorldHint: false,
    },
  },
  {
    name: "add_cards",
    title: "Add cards to a deck",
    description:
      `Adds up to ${MAX_CARDS} new cards to one of the signed-in user's decks; send more in several calls. Each card is {"blocks":[...]}, a list of text, senses, cloze, table and image blocks, or the plain front (the word or question) and back (its meaning or answer) with optional labels and examples. Read the resource ${GUIDE_URI} for which form fits. A card needs something shown first and something added at the reveal; a cloze, a table or an image with boxes counts for both. At most ${MAX_PHOTOS} photos are fetched per call. It never changes or deletes a card. A card whose first-shown text matches a card already in the deck, or an earlier card in the same call (ignoring case, spacing and width), is skipped as a duplicate unless allow_duplicates is true. The answer lists the cards added, those skipped as duplicates and those refused, each with its index in the request and why. The cards appear on the user's phone and on the web at their next sync.`,
    inputSchema: {
      type: "object",
      properties: {
        deck_id: deckId,
        cards: {
          type: "array",
          minItems: 1,
          maxItems: MAX_CARDS,
          items: {
            anyOf: [
              {
                type: "object",
                properties: {
                  blocks: {
                    type: "array",
                    minItems: 1,
                    maxItems: MAX_BLOCKS,
                    items: blockIn,
                  },
                },
                required: ["blocks"],
                additionalProperties: false,
              },
              {
                type: "object",
                properties: {
                  front: { type: "string", minLength: 1, maxLength: MAX_TEXT },
                  back: { type: "string", minLength: 1, maxLength: MAX_TEXT },
                  labels: labelsField,
                  examples: examplesField,
                },
                required: ["front", "back"],
                additionalProperties: false,
              },
            ],
          },
        },
        allow_duplicates: {
          type: "boolean",
          default: false,
          description:
            "Add a card even when its front matches one already in the deck. Set it only when the user asked for the second card.",
        },
      },
      required: ["deck_id", "cards"],
      additionalProperties: false,
    },
    outputSchema: {
      type: "object",
      properties: {
        deck: deckOut,
        added: {
          type: "array",
          items: {
            type: "object",
            properties: {
              index: { type: "integer" },
              id: { type: "string" },
              front: { type: "string" },
            },
            required: ["index", "id", "front"],
          },
        },
        skipped: {
          type: "array",
          items: {
            type: "object",
            properties: {
              index: { type: "integer" },
              front: { type: "string" },
              reason: { type: "string" },
              existing_card_id: { type: "string" },
            },
            required: ["index", "front", "reason", "existing_card_id"],
          },
        },
        refused: {
          type: "array",
          items: {
            type: "object",
            properties: {
              index: { type: "integer" },
              reason: { type: "string" },
            },
            required: ["index", "reason"],
          },
        },
      },
      required: ["deck", "added", "skipped", "refused"],
    },
    annotations: {
      readOnlyHint: false,
      destructiveHint: false,
      openWorldHint: false,
    },
  },
] as const;

/** The dependencies a call needs beyond the caller's store. */
export type ToolDeps = IdSource & Omit<PhotoDeps, "fetch">;

type Args = Record<string, unknown>;

function isRecord(value: unknown): value is Args {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

/** An optional integer argument in [min, max], or a refusal naming it. */
function integer(
  args: Args,
  name: string,
  fallback: number,
  min: number,
  max: number,
): number | string {
  const value = args[name] ?? fallback;
  return Number.isInteger(value) && (value as number) >= min &&
      (value as number) <= max
    ? value as number
    : `${name} must be a whole number from ${min} to ${max}.`;
}

const NOT_FOUND =
  "No deck of the signed-in user has that deck_id, or it was deleted. Call list_decks for the ids of the user's decks.";

/** Runs the tool [name] with [args] for the caller behind [store]. */
export async function callTool(
  name: string,
  args: unknown,
  store: Store,
  deps: ToolDeps,
): Promise<ToolResult> {
  const input = args === undefined ? {} : args;
  if (!isRecord(input)) return refuse("The arguments must be a JSON object.");
  switch (name) {
    case "list_decks":
      return result({ decks: await listDecks(store) });
    case "list_cards":
      return await listCardsTool(input, store);
    case "search_cards":
      return await searchCards(input, store);
    case "create_deck":
      return await createDeck(input, store, deps);
    case "add_cards":
      return await addCards(input, store, deps);
    default:
      return refuse(
        `There is no tool named ${name}. The tools are ${
          TOOLS.map((t) => t.name).join(", ")
        }.`,
      );
  }
}

function deckIdOf(args: Args): string | null {
  const value = args.deck_id;
  return typeof value === "string" && UUID.test(value.toLowerCase())
    ? value.toLowerCase()
    : null;
}

/** A stored card as the read tools return it; one that does not parse says so by its one block. */
function cardOf(card: StoredSides & { id: string }) {
  const cells = cellsOf(card);
  return {
    id: card.id,
    blocks: cells === null
      ? [{ type: "unknown", stored_type: "unreadable" }]
      : blocksOut(cells),
  };
}

async function listCardsTool(args: Args, store: Store): Promise<ToolResult> {
  const id = deckIdOf(args);
  if (id === null) {
    return refuse(
      "deck_id must be a deck's id, a uuid, as list_decks returns it.",
    );
  }
  const offset = integer(args, "offset", 0, 0, Number.MAX_SAFE_INTEGER);
  if (typeof offset === "string") return refuse(offset);
  const limit = integer(args, "limit", 50, 1, 100);
  if (typeof limit === "string") return refuse(limit);
  const deck = await readDeck(store, id);
  if (deck === null) return refuse(NOT_FOUND);
  const { cards, total } = await listCards(store, id, offset, limit);
  const next = offset + cards.length;
  return result({
    deck,
    total,
    cards: cards.map(cardOf),
    next_offset: cards.length > 0 && next < total ? next : null,
  });
}

/** Text compared ignoring case, width and spacing, as the duplicate key compares fronts. */
const comparable = (text: string) => cardKey(text);

async function searchCards(args: Args, store: Store): Promise<ToolResult> {
  const query = typeof args.query === "string" ? comparable(args.query) : "";
  if (query === "" || query.length > 200) {
    return refuse("query must be text of 1 to 200 characters.");
  }
  const limit = integer(args, "limit", 20, 1, 100);
  if (typeof limit === "string") return refuse(limit);
  const [decks, cards] = await Promise.all([listDecks(store), allCards(store)]);
  const names = new Map(decks.map((deck) => [deck.id, deck.name]));
  const found = cards.flatMap((card) => {
    const name = names.get(card.deck_id);
    if (name === undefined) return [];
    const cells = cellsOf(card);
    return cells !== null && comparable(searchText(cells)).includes(query)
      ? [{ ...cardOf(card), deck: { id: card.deck_id, name } }]
      : [];
  });
  return result({
    cards: found.slice(0, limit),
    truncated: found.length > limit,
  });
}

/** A text argument trimmed, or null when it is not text, is empty or is longer than [max]. */
function trimmed(value: unknown, max: number): string | null {
  if (typeof value !== "string") return null;
  const text = value.trim();
  return text === "" || text.length > max ? null : text;
}

async function createDeck(
  args: Args,
  store: Store,
  deps: ToolDeps,
): Promise<ToolResult> {
  const name = trimmed(args.name, MAX_NAME);
  if (name === null) {
    return refuse(`name must be text of 1 to ${MAX_NAME} characters.`);
  }
  const id = uuidV7(deps);
  const now = new Date(deps.now()).toISOString();
  await insert(store, "decks", [{
    id,
    user_id: store.userId,
    name,
    visibility: "private",
    created_at: now,
    updated_at: now,
  }]);
  return result({ deck: { id, name } });
}

/** [card]'s blocks with its photos fetched and stored, or the sentence refusing the card. */
async function withPhotos(
  card: ReadCard,
  store: Store,
  deps: ToolDeps,
): Promise<readonly StoredBlock[] | string> {
  const sizes = new Map<unknown, { width: number; height: number }>();
  for (const { media, url } of card.photos) {
    const photo = await fetchPhoto(url, { ...deps, fetch: store.fetch });
    if (typeof photo === "string") return photo;
    try {
      await storePhoto(store, media, photo);
    } catch (error) {
      if (!(error instanceof SupabaseError)) throw error;
      return "The photo could not be stored: try this card again in a moment.";
    }
    sizes.set(media, { width: photo.width, height: photo.height });
  }
  return card.blocks.map((block) => {
    const size = sizes.get(block.payload.media);
    return size ? { ...block, payload: { ...block.payload, ...size } } : block;
  });
}

async function addCards(
  args: Args,
  store: Store,
  deps: ToolDeps,
): Promise<ToolResult> {
  const id = deckIdOf(args);
  if (id === null) {
    return refuse(
      "deck_id must be a deck's id, a uuid, as list_decks returns it.",
    );
  }
  const input = args.cards;
  if (!Array.isArray(input) || input.length === 0) {
    return refuse(
      "cards must be a list of 1 to 100 cards, each with blocks, or with front and back.",
    );
  }
  if (input.length > MAX_CARDS) {
    return refuse(
      `add_cards takes at most ${MAX_CARDS} cards per call, and this call has ${input.length}. Nothing was added. Send the cards in calls of ${MAX_CARDS} or fewer.`,
    );
  }
  const allowDuplicates = args.allow_duplicates ?? false;
  if (typeof allowDuplicates !== "boolean") {
    return refuse("allow_duplicates must be true or false.");
  }
  const deck = await readDeck(store, id);
  if (deck === null) return refuse(NOT_FOUND);
  const keys = await deckKeys(store, id);
  const start = deps.now();
  const added: { index: number; id: string; front: string }[] = [];
  const skipped: {
    index: number;
    front: string;
    reason: string;
    existing_card_id: string;
  }[] = [];
  const refused: { index: number; reason: string }[] = [];
  const rows: Record<string, unknown>[] = [];
  let photosLeft = MAX_PHOTOS;
  for (const [index, value] of input.entries()) {
    const card = readCard(value, deps);
    if (typeof card === "string") {
      refused.push({ index, reason: card });
      continue;
    }
    const existing = keys.get(card.key);
    if (existing !== undefined && !allowDuplicates) {
      skipped.push({
        index,
        front: card.front,
        reason: "a card with the same first-shown text is already in the deck",
        existing_card_id: existing,
      });
      continue;
    }
    if (card.photos.length > photosLeft) {
      refused.push({
        index,
        reason:
          `add_cards fetches at most ${MAX_PHOTOS} photos per call: send this card in another call.`,
      });
      continue;
    }
    photosLeft -= card.photos.length;
    const blocks = await withPhotos(card, store, deps);
    if (typeof blocks === "string") {
      refused.push({ index, reason: blocks });
      continue;
    }
    const cardId = uuidV7(deps);
    keys.set(card.key, cardId);
    // A deck lists its cards by creation time: one millisecond apart keeps the request's order.
    const now = new Date(start + rows.length).toISOString();
    rows.push({
      id: cardId,
      deck_id: id,
      user_id: store.userId,
      front: blocks,
      back: [],
      card_key: card.key,
      source: "import",
      template: "free",
      template_version: 2,
      created_at: now,
      updated_at: now,
    });
    added.push({ index, id: cardId, front: card.front });
  }
  if (rows.length > 0) await insert(store, "cards", rows);
  return result({ deck, added, skipped, refused });
}
