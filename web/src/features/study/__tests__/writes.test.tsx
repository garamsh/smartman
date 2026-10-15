import { render, screen, waitFor, within } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";

import type { Card, CardId, DeckId } from "@/features/decks";
import { day, start } from "@/testing/library";
import { testUser } from "@/testing/mocks/handlers";
import { FakePostgrest } from "@/testing/mocks/postgrest";
import { server } from "@/testing/mocks/server";
import { setRequestCookies } from "@/testing/next-headers";
import { signedInCookies } from "@/testing/session";

import { StudyScreen } from "../components/study-screen";
import { schedule } from "../engine";
import type { CardState } from "../queue";

vi.mock("next/headers", () => import("@/testing/next-headers"));

const iso = (time: number) => new Date(time).toISOString();

const card: Card = {
  id: "c1" as CardId,
  deckId: "d1" as DeckId,
  front: [{ kind: "text", text: "chat" }],
  back: [{ kind: "text", text: "cat" }],
  createdAt: start - day,
};

/** The engine's state for [card] after [answer] at [at] with [fuzzFactor], from [before]. */
async function expected(
  before: CardState | null,
  answer: "know" | "dontKnow",
  at: number,
  fuzzFactor: number,
) {
  const scheduled = await schedule(before, [{ answer, reviewedAt: at, fuzzFactor }]);
  if (!("state" in scheduled)) throw new Error(`the engine refused: ${JSON.stringify(scheduled)}`);
  return scheduled.state;
}

/** The stored fuzz factor of the session's only review. */
function storedFactor(postgrest: FakePostgrest): number {
  const factor = postgrest.rows.reviews[0]?.fuzz_factor;
  if (typeof factor !== "number") throw new Error("the review carries no fuzz factor");
  return factor;
}

describe("a study session's writes", () => {
  let postgrest: FakePostgrest;
  beforeEach(async () => {
    vi.useFakeTimers({ toFake: ["Date"] });
    vi.setSystemTime(start);
    setRequestCookies(await signedInCookies());
    postgrest = new FakePostgrest();
    server.use(...postgrest.handlers);
  });
  afterEach(() => {
    vi.useRealTimers();
  });

  it("writes one review per answer and the card state the engine computes", async () => {
    // A long interval, so the answer's fuzz factor moves the due day.
    const before = { stability: 20, difficulty: 5, lastReview: start - 20 * day, due: start - day };
    render(
      <StudyScreen plan={{ startedAt: start, cards: [card], before: { [card.id]: before } }} />,
    );

    vi.setSystemTime(start + 4000);
    await userEvent.setup().keyboard("k");

    await waitFor(() => {
      expect(postgrest.rows.card_states).toHaveLength(1);
    });
    expect(postgrest.rows.reviews).toHaveLength(1);
    expect(postgrest.rows.reviews[0]).toMatchObject({
      user_id: testUser.id,
      card_id: "c1",
      rating: "good",
      reviewed_at: iso(start + 4000),
      duration_ms: 4000,
      updated_at: iso(start + 4000),
    });
    const state = await expected(before, "know", start + 4000, storedFactor(postgrest));
    expect(postgrest.rows.card_states[0]).toMatchObject({
      user_id: testUser.id,
      card_id: "c1",
      stability: state.stability,
      difficulty: state.difficulty,
      last_review: iso(state.lastReview),
      due: iso(state.due),
      updated_at: iso(start + 4000),
      deleted_at: null,
    });
  });

  it("schedules a new card's first answer from no state", async () => {
    render(<StudyScreen plan={{ startedAt: start, cards: [card], before: {} }} />);

    vi.setSystemTime(start + 4000);
    await userEvent.setup().keyboard("j");

    await waitFor(() => {
      expect(postgrest.rows.card_states).toHaveLength(1);
    });
    expect(postgrest.rows.reviews[0]).toMatchObject({ rating: "again", duration_ms: 4000 });
    const state = await expected(null, "dontKnow", start + 4000, storedFactor(postgrest));
    expect(postgrest.rows.card_states[0]).toMatchObject({
      stability: state.stability,
      difficulty: state.difficulty,
      due: iso(state.due),
    });
  });

  it("rewrites a toggled answer by replaying it with its stored fuzz factor", async () => {
    // A long interval, so the fuzz factor moves the due day.
    const before = { stability: 20, difficulty: 5, lastReview: start - 20 * day, due: start - day };
    render(
      <StudyScreen plan={{ startedAt: start, cards: [card], before: { [card.id]: before } }} />,
    );
    const user = userEvent.setup();
    const stateEditedAt = (at: number) => async () => {
      await waitFor(() => {
        expect(postgrest.rows.card_states[0]?.updated_at).toBe(iso(at));
      });
    };
    const toggle = async (at: number) => {
      vi.setSystemTime(at);
      await user.click(within(screen.getByRole("region", { name: "이전 답" })).getByRole("button"));
      await stateEditedAt(at)();
    };
    const answeredAt = start + 2000;
    vi.setSystemTime(answeredAt);
    await user.keyboard("k");
    await stateEditedAt(answeredAt)();
    const fuzzFactor = storedFactor(postgrest);
    const known = await expected(before, "know", answeredAt, fuzzFactor);

    await toggle(start + 3000);
    const unknown = await expected(before, "dontKnow", answeredAt, fuzzFactor);
    expect(postgrest.rows.reviews).toHaveLength(1);
    expect(postgrest.rows.reviews[0]).toMatchObject({
      rating: "again",
      fuzz_factor: fuzzFactor,
      updated_at: iso(start + 3000),
    });
    expect(postgrest.rows.card_states[0]).toMatchObject({
      stability: unknown.stability,
      due: iso(unknown.due),
    });

    await toggle(start + 4000);
    expect(postgrest.rows.reviews[0]).toMatchObject({ rating: "good", fuzz_factor: fuzzFactor });
    expect(postgrest.rows.card_states[0]).toMatchObject({
      stability: known.stability,
      difficulty: known.difficulty,
      last_review: iso(known.lastReview),
      due: iso(known.due),
    });
    // Control: another factor schedules the answer to another day, so the stored one was used.
    const otherFactor = await expected(before, "know", answeredAt, (fuzzFactor + 0.5) % 1);
    expect(otherFactor.due).not.toBe(known.due);
  });
});
