/**
 * The five tools a model calls: their definitions, written for a model that has no other
 * documentation, and their calls, each answering a result or a refusal the model can act on.
 */

import {
  cardKey,
  type IdSource,
  isWholeCard,
  labelsOf,
  PART_OF_SPEECH_FORMS,
  sides,
  sideText,
  uuidV7,
} from "./cards.ts";
import {
  allCards,
  deckKeys,
  insert,
  listCards,
  listDecks,
  readDeck,
  type Store,
} from "./store.ts";

/** The most cards one `add_cards` call takes. */
export const MAX_CARDS = 100;
/** The longest a deck's name may be, as on the web. */
const MAX_NAME = 500;
/** The longest a card's front, back, label or example may be. */
const MAX_TEXT = 2000;
const MAX_EXAMPLES = 10;
const MAX_LABELS = 10;

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
const cardOut = {
  type: "object",
  properties: {
    id: { type: "string" },
    front: { type: "string", description: "The front as text." },
    back: {
      type: "string",
      description:
        "The back as text; empty for a cloze or table card, whose answer is its front.",
    },
  },
  required: ["id", "front", "back"],
};

/** The tools as `tools/list` returns them. */
export const TOOLS = [
  {
    name: "list_decks",
    title: "List decks",
    description:
      "Lists the signed-in user's Smartman flashcard decks, oldest first, each with its id, name and number of cards. Call it first to find the deck_id the other tools take.",
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
      "Lists one deck's cards, oldest first, a page at a time. Each card has a front and a back as text; a meaning's labels are in brackets, such as [명], and its examples follow on lines starting with '-'. To read the next page, call again with offset set to next_offset; next_offset is null on the last page.",
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
      "Finds the signed-in user's cards, across all their decks, whose front or back contains the query, ignoring case. A cloze or table card is matched on its front alone. Returns at most limit cards, each with its deck.",
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
      `Adds up to ${MAX_CARDS} new cards to one of the signed-in user's decks; send more in several calls. Each card has a front (the word or question) and a back (its meaning or answer), and optionally labels and examples for the meaning. It never changes or deletes a card. A card whose front matches a card already in the deck, or an earlier card in the same call (ignoring case, spacing and width), is skipped as a duplicate unless allow_duplicates is true. The answer lists the cards added, those skipped as duplicates and those refused, each with its index in the request and why. The cards appear on the user's phone and on the web at their next sync.`,
    inputSchema: {
      type: "object",
      properties: {
        deck_id: deckId,
        cards: {
          type: "array",
          minItems: 1,
          maxItems: MAX_CARDS,
          items: {
            type: "object",
            properties: {
              front: { type: "string", minLength: 1, maxLength: MAX_TEXT },
              back: { type: "string", minLength: 1, maxLength: MAX_TEXT },
              labels: {
                type: "array",
                maxItems: MAX_LABELS,
                items: { type: "string" },
                description:
                  `Labels shown in brackets before the meaning. A part of speech is one of these short forms: ${
                    PART_OF_SPEECH_FORMS.join(", ")
                  } (명 noun, 동 verb, 형 adjective, 부 adverb, 대 pronoun, 전 preposition, 접 conjunction, 감 interjection, 관 determiner, 수 numeral, 조 particle, 조동 auxiliary, 양 classifier, 구 phrase); any other text is stored as a label of its own.`,
              },
              examples: {
                type: "array",
                maxItems: MAX_EXAMPLES,
                items: { type: "string" },
                description: "Example sentences for the meaning.",
              },
            },
            required: ["front", "back"],
            additionalProperties: false,
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
export type ToolDeps = IdSource;

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

function face(card: { front: unknown; back: unknown }) {
  return {
    front: sideText(card.front),
    back: isWholeCard(card.front) ? "" : sideText(card.back),
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
    cards: cards.map((card) => ({ id: card.id, ...face(card) })),
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
    const shown = face(card);
    const matches = comparable(shown.front).includes(query) ||
      comparable(shown.back).includes(query);
    return matches
      ? [{ id: card.id, ...shown, deck: { id: card.deck_id, name } }]
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

/** A card of an `add_cards` call, read, or the reason it is refused. */
function readCard(value: unknown) {
  if (!isRecord(value)) {
    return "the card must be an object with front and back.";
  }
  const front = trimmed(value.front, MAX_TEXT);
  if (front === null) {
    return `front must be text of 1 to ${MAX_TEXT} characters.`;
  }
  const back = trimmed(value.back, MAX_TEXT);
  if (back === null) return `back must be text of 1 to ${MAX_TEXT} characters.`;
  const list = (field: string, max: number): string[] | string => {
    const items = value[field] ?? [];
    if (!Array.isArray(items) || items.length > max) {
      return `${field} must be a list of at most ${max} texts.`;
    }
    const texts = items.map((item) => trimmed(item, MAX_TEXT));
    return texts.includes(null)
      ? `each of ${field} must be text of 1 to ${MAX_TEXT} characters.`
      : texts as string[];
  };
  const labels = list("labels", MAX_LABELS);
  if (typeof labels === "string") return labels;
  const examples = list("examples", MAX_EXAMPLES);
  if (typeof examples === "string") return examples;
  return { front, back, labels: labelsOf(labels), examples };
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
      "cards must be a list of 1 to 100 cards, each with front and back.",
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
  input.forEach((value, index) => {
    const card = readCard(value);
    if (typeof card === "string") {
      refused.push({ index, reason: card });
      return;
    }
    const key = cardKey(card.front);
    const existing = keys.get(key);
    if (existing !== undefined && !allowDuplicates) {
      skipped.push({
        index,
        front: card.front,
        reason: "a card with the same front is already in the deck",
        existing_card_id: existing,
      });
      return;
    }
    const cardId = uuidV7(deps);
    keys.set(key, cardId);
    // A deck lists its cards by creation time: one millisecond apart keeps the request's order.
    const now = new Date(start + rows.length).toISOString();
    rows.push({
      id: cardId,
      deck_id: id,
      user_id: store.userId,
      ...sides(card, deps),
      card_key: key,
      source: "import",
      template: "free",
      template_version: 1,
      created_at: now,
      updated_at: now,
    });
    added.push({ index, id: cardId, front: card.front });
  });
  if (rows.length > 0) await insert(store, "cards", rows);
  return result({ deck, added, skipped, refused });
}
