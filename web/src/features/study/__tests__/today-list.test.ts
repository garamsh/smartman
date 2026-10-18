import { beforeAll, describe, expect, it } from "vitest";

import type { CardId } from "@/features/decks";

import { loadEngine } from "../engine";
import { todayOf, withTodaysLeft } from "../today-list";

beforeAll(loadEngine);

const hour = 3_600_000;
/** 2026-10-18 04:00 UTC to 2026-10-19 04:00 UTC. */
const day = { start: Date.UTC(2026, 9, 18, 4), end: Date.UTC(2026, 9, 19, 4) };
const id = (name: string) => name as CardId;
const state = (due: number) => ({ stability: 1, difficulty: 5, lastReview: day.start, due });

describe("today's list, through the engine's WebAssembly", () => {
  it("places each card by its due time and its latest answer of the day", () => {
    const places = todayOf(
      ["due", "failed", "passed", "tomorrow", "new"].map(id),
      {
        [id("due")]: state(day.start + 5 * hour),
        [id("failed")]: state(day.end + hour),
        [id("passed")]: state(day.end + hour),
        [id("tomorrow")]: state(day.end + hour),
      },
      [
        { cardId: id("failed"), answer: "dontKnow", reviewedAt: day.start + hour },
        { cardId: id("passed"), answer: "dontKnow", reviewedAt: day.start + hour },
        { cardId: id("passed"), answer: "know", reviewedAt: day.start + 2 * hour },
        // Before the day began: not today's.
        { cardId: id("tomorrow"), answer: "dontKnow", reviewedAt: day.start - hour },
      ],
      day,
    );
    expect(Object.fromEntries(places)).toEqual({
      due: "left",
      failed: "left",
      passed: "done",
      tomorrow: "absent",
      new: "absent",
    });
  });

  it("adds to the selected queue the cards left that it did not select, after them", () => {
    const cards = ["a", "b", "c", "d"].map((name) => ({ id: id(name) }));
    const [a, b, c] = cards;
    if (!a || !b || !c) throw new Error("four cards");
    const places = new Map([
      [id("a"), "left" as const],
      [id("b"), "done" as const],
      [id("c"), "left" as const],
      [id("d"), "absent" as const],
    ]);
    expect(withTodaysLeft({ cards: [a], backlog: true }, cards, places)).toEqual({
      cards: [a, c],
      backlog: true,
    });
  });
});
