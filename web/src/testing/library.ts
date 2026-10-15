import { testUser } from "./mocks/handlers";
import type { FakePostgrest } from "./mocks/postgrest";

/** A day, in milliseconds. */
export const day = 86_400_000;

/**
 * The time a test's clock is set to. It is in the past, so the test session's access token,
 * which expires an hour after the real time, is still valid at it.
 */
export const start = Date.UTC(2026, 0, 15, 9);

const iso = (time: number) => new Date(time).toISOString();

/** A text card side, as the phone stores it. */
export const side = (text: string) => [{ type: "text", payload: { text } }];

/** A deck row as the phone's sync pushes it, private unless [visibility] says otherwise. */
export function deckRow(
  id: string,
  name: string,
  deleted = false,
  visibility: "private" | "public" = "private",
) {
  return {
    id,
    user_id: testUser.id,
    name,
    visibility,
    created_at: iso(start - 30 * day),
    updated_at: iso(start - 30 * day),
    deleted_at: deleted ? iso(start - day) : null,
  };
}

/** A card row as the phone's sync pushes it, created [age] milliseconds before [start]. */
export function cardRow(id: string, deckId: string, front: string, age = day, deleted = false) {
  return {
    id,
    user_id: testUser.id,
    deck_id: deckId,
    front: side(front),
    back: side(`${front} back`),
    card_key: front.toLowerCase(),
    source: "manual",
    created_at: iso(start - age),
    updated_at: iso(start - age),
    deleted_at: deleted ? iso(start - day) : null,
  };
}

/** A stored card state, last reviewed at [lastReview] and due at [due]. */
export function stateRow(
  cardId: string,
  state: { stability: number; difficulty: number; lastReview: number; due: number },
) {
  return {
    user_id: testUser.id,
    card_id: cardId,
    stability: state.stability,
    difficulty: state.difficulty,
    last_review: iso(state.lastReview),
    due: iso(state.due),
    updated_at: iso(state.lastReview),
    deleted_at: null,
  };
}

/** A review of [cardId] as the phone's sync pushes it, given at [reviewedAt] after [durationMs]. */
export function reviewRow(id: string, cardId: string, reviewedAt: number, durationMs: number) {
  return {
    id,
    user_id: testUser.id,
    card_id: cardId,
    rating: "good",
    reviewed_at: iso(reviewedAt),
    duration_ms: durationMs,
    fuzz_factor: null,
    updated_at: iso(reviewedAt),
    deleted_at: null,
  };
}

/** Seeds one deck, [deckId], holding a new card for each of [fronts], the first the oldest. */
export function seedDeck(postgrest: FakePostgrest, deckId: string, fronts: string[]) {
  postgrest.seed("decks", deckRow(deckId, deckId));
  postgrest.seed(
    "cards",
    ...fronts.map((front, index) =>
      cardRow(`${deckId}-${String(index)}`, deckId, front, (fronts.length - index) * 1000),
    ),
  );
}
