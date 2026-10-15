import { describe, expect, it } from "vitest";

import type { CardId } from "@/features/decks";

import {
  backlogBucketSize,
  backlogDays,
  type CardState,
  type CardStates,
  countToday,
  dailyLoad,
  orderQueue,
  selectQueue,
} from "../queue";
import { type Random, seededRandom } from "../random";

const day = 86_400_000;
const hour = 3_600_000;
const now = Date.UTC(2026, 0, 15, 9);

type TestCard = { id: CardId; createdAt: number };

const card = (id: string): TestCard => ({ id: id as CardId, createdAt: now });
const ids = (cards: readonly TestCard[]) => cards.map((each) => each.id as string);

/** A state due at [due] after an interval of [days] days. */
const dueAfter = (due: number, days: number): CardState => ({
  stability: days,
  difficulty: 5,
  lastReview: due - days * day,
  due,
});

/** A source that always draws 0, which keeps every order selected. */
const firstDraw: Random = { nextInt: () => 0, nextDouble: () => 0 };

const fresh = [card("new0"), card("new1")];

/**
 * [count] reviewed cards, each after an interval of four days, so their daily load is a
 * quarter of [count]; the first [due] of them are due.
 */
function reviewed(count: number, due: number): [TestCard[], CardStates] {
  const cards = Array.from({ length: count }, (_, index) => card(`review${String(index)}`));
  const states: CardStates = {};
  cards.forEach((each, index) => {
    states[each.id] = dueAfter(index < due ? now : now + day, 4);
  });
  return [cards, states];
}

// Thirty cards due at distinct times, each after a 30-day interval: thirty due against a daily
// load of one is a backlog. Given latest due first, so only sorting puts the earliest first.
const latestFirst = Array.from({ length: 30 }, (_, index) => card(`overdue${String(index)}`));
const overdueStates: CardStates = {};
latestFirst.forEach((each, index) => {
  overdueStates[each.id] = dueAfter(now - index * hour, 30);
});
const earliestFirst = ids(latestFirst).reverse();

describe("the study queue", () => {
  it("pauses new cards once more than three days of reviews are due, and takes them at three", () => {
    expect(backlogDays).toBe(3);
    // Twelve cards due every four days are three reviews a day.
    const [atThreshold, atStates] = reviewed(12, 9);
    const [over, overStates] = reviewed(12, 10);
    expect(dailyLoad(Object.values(atStates).filter((state) => state !== undefined))).toBe(3);

    const current = selectQueue([...atThreshold, ...fresh], atStates, now);
    const paused = selectQueue([...over, ...fresh], overStates, now);

    expect(current.backlog).toBe(false);
    expect(ids(current.cards).sort()).toEqual(
      [...ids(atThreshold.slice(0, 9)), "new0", "new1"].sort(),
    );
    expect(countToday([...atThreshold, ...fresh], atStates, now)).toEqual({
      review: 9,
      fresh: 2,
      backlog: false,
    });
    expect(paused.backlog).toBe(true);
    expect(ids(paused.cards).sort()).toEqual(ids(over.slice(0, 10)).sort());
    expect(countToday([...over, ...fresh], overStates, now)).toEqual({
      review: 10,
      fresh: 0,
      backlog: true,
    });
  });

  it("in a backlog, puts the due cards earliest due first, equal due times in the order given", () => {
    const tied = card("tied");
    const last = latestFirst.at(-1);
    if (!last) throw new Error("no overdue card");
    const states = { ...overdueStates, [tied.id]: overdueStates[last.id] };

    const selected = selectQueue([...latestFirst, tied, ...fresh], states, now);

    expect(selected.backlog).toBe(true);
    expect(ids(selected.cards)).toEqual([earliestFirst[0], "tied", ...earliestFirst.slice(1)]);
    // An all-zero source keeps that order.
    expect(ids(orderQueue(selected, firstDraw))).toEqual(ids(selected.cards));
  });

  it("in a backlog, keeps each run of ten in its place in the order and shuffles it within", () => {
    expect(backlogBucketSize).toBe(10);
    const selected = selectQueue(latestFirst, overdueStates, now);
    const runs = [0, 10, 20].map((start) => [...earliestFirst.slice(start, start + 10)].sort());
    const orders = new Set<string>();

    for (let seed = 0; seed < 50; seed++) {
      const ordered = ids(orderQueue(selected, seededRandom(seed)));
      runs.forEach((run, index) => {
        expect([...ordered.slice(index * 10, index * 10 + 10)].sort()).toEqual(run);
      });
      orders.add(ordered.join(","));
    }
    // Control: the runs are shuffled, not kept in the order selected.
    expect(orders.size).toBe(50);
  });

  it("shuffles an up-to-date collection as a whole, not in runs, with its new cards", () => {
    // Thirty cards due daily: thirty due against a load of thirty.
    const states: CardStates = {};
    for (const each of latestFirst) states[each.id] = dueAfter(now, 1);
    const selected = selectQueue([...latestFirst, ...fresh], states, now);

    expect(selected.backlog).toBe(false);
    expect(selected.cards).toHaveLength(32);
    const firsts = new Set<string>();
    for (let seed = 0; seed < 200; seed++) {
      const [first] = ids(orderQueue(selected, seededRandom(seed)));
      if (first) firsts.add(first);
    }
    const firstRun = new Set(ids(selected.cards.slice(0, 10)));
    // Cards from past the first run of ten, new ones included, come first.
    expect([...firsts].some((id) => !firstRun.has(id))).toBe(true);
    expect([...firsts]).toEqual(expect.arrayContaining(["new0", "new1"]));
  });
});
