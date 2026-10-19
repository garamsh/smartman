import { beforeAll, describe, expect, it } from "vitest";

import type { CardId } from "@/features/decks";

import { loadEngine } from "../engine";
import { dailyGoal } from "../overview";
import { studyDay } from "../queue";
import { countDay, dayPlanOf, todayOf } from "../today-list";

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

  it("plans the day: the selection, the cards still on 모른다 it did not select, and those done", () => {
    const card = (name: string) => ({ id: id(name), createdAt: day.start - 30 * 86_400_000 });
    const cards = ["due", "failed", "passed", "new"].map(card);
    const plan = dayPlanOf(
      cards,
      {
        [id("due")]: state(day.start + 5 * hour),
        [id("failed")]: state(day.end + hour),
        [id("passed")]: state(day.end + hour),
      },
      { ...day, newCardsLeft: 20 },
      [
        { cardId: id("failed"), answer: "dontKnow", reviewedAt: day.start + hour },
        { cardId: id("passed"), answer: "know", reviewedAt: day.start + hour },
      ],
    );
    expect(plan.selected.cards.map((card) => card.id)).toEqual(["due", "new"]);
    expect(plan.relearn.map((card) => card.id)).toEqual(["failed"]);
    expect([...plan.done]).toEqual(["passed"]);
    // The card still on 모른다 counts as a review.
    expect(
      countDay(plan, { [id("due")]: state(day.start), [id("failed")]: state(day.end) }),
    ).toEqual({
      review: 2,
      fresh: 1,
      backlog: false,
    });
  });

  /**
   * Twelve reviewed cards, each after an interval of four days, so their daily load is three;
   * the first [due] of them are due today, the others tomorrow; and two new cards.
   */
  function reviewedDay(due: number) {
    const card = (name: string) => ({ id: id(name), createdAt: day.start - 30 * 86_400_000 });
    const reviewed = Array.from({ length: 12 }, (_, index) => card(`review${String(index)}`));
    const states = Object.fromEntries(
      reviewed.map((each, index) => {
        const at = index < due ? day.start + hour : day.end + hour;
        return [each.id, { stability: 4, difficulty: 5, lastReview: at - 4 * 86_400_000, due: at }];
      }),
    );
    return { cards: [...reviewed, card("new0"), card("new1")], states };
  }

  it("counts a backlog's due cards as reviews and no new card, and below it takes the new cards", () => {
    const over = reviewedDay(10);
    const backlog = dayPlanOf(over.cards, over.states, { ...day, newCardsLeft: 20 }, []);
    expect(countDay(backlog, over.states)).toEqual({ review: 10, fresh: 0, backlog: true });
    // Control: nine due is three days of reviews, the threshold, so the day takes both new cards.
    const at = reviewedDay(9);
    const usual = dayPlanOf(at.cards, at.states, { ...day, newCardsLeft: 20 }, []);
    expect(countDay(usual, at.states)).toEqual({ review: 9, fresh: 2, backlog: false });
  });

  it("counts no more new cards than the day has left", () => {
    const none = reviewedDay(0);
    for (const [left, fresh] of [
      [0, 0],
      [1, 1],
      [20, 2],
    ] as const) {
      const plan = dayPlanOf(none.cards, none.states, { ...day, newCardsLeft: left }, []);
      expect(countDay(plan, none.states)).toEqual({ review: 0, fresh, backlog: false });
    }
  });
});

const now = Date.UTC(2026, 9, 14, 9);
/** A day of 20 new cards, as the daily minutes would set it. */
const goalDay = studyDay(now, [], "UTC", 20);
const msPerDay = 86_400_000;

describe("the daily goal", () => {
  it("is the day's cards done and left as today's list places them, a card on 모른다 left until 안다", () => {
    const card = (value: string) => ({ id: id(value), createdAt: now - 30 * msPerDay });
    const later = { stability: 3, difficulty: 5, lastReview: now, due: now + msPerDay };
    const states = {
      [id("a")]: later,
      [id("b")]: later,
      [id("c")]: { ...later, due: now - msPerDay },
      [id("z")]: later,
    };
    const answers = [
      { cardId: id("a"), answer: "know" as const, reviewedAt: goalDay.start + 1000 },
      { cardId: id("b"), answer: "dontKnow" as const, reviewedAt: goalDay.start + 3000 },
      // Yesterday's answer is no part of today's goal.
      { cardId: id("z"), answer: "dontKnow" as const, reviewedAt: goalDay.start - 1000 },
    ];
    const cards = ["a", "b", "c", "z"].map(card);
    // a is done; b, answered 모른다, and c, due, are left.
    expect(dailyGoal(dayPlanOf(cards, states, goalDay, answers))).toEqual({ done: 1, goal: 3 });
    // Answered 안다 later, b is done.
    const known = [
      ...answers,
      { cardId: id("b"), answer: "know" as const, reviewedAt: goalDay.start + 4000 },
    ];
    expect(dailyGoal(dayPlanOf(cards, states, goalDay, known))).toEqual({ done: 2, goal: 3 });
  });
});
