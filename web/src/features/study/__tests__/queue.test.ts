import { describe, expect, it } from "vitest";

import type { CardId } from "@/features/decks";

import {
  backlogBucketSize,
  backlogDays,
  type CardState,
  type CardStates,
  dailyLoad,
  orderQueue,
  selectQueue,
  streak,
  studyDay,
  studyDayStart,
  studyDayStartHour,
} from "../queue";
import { type Random, seededRandom } from "../random";

const day = 86_400_000;
/** The new cards a day takes in these cases, as the daily minutes would set them. */
const quota = 20;
const hour = 3_600_000;
const now = Date.UTC(2026, 0, 15, 9);
/** The study day holding [now] in UTC, with no new card answered in it. */
const today = studyDay(now, [], "UTC", quota);

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

    const current = selectQueue([...atThreshold, ...fresh], atStates, today);
    const paused = selectQueue([...over, ...fresh], overStates, today);

    expect(current.backlog).toBe(false);
    expect(ids(current.cards).sort()).toEqual(
      [...ids(atThreshold.slice(0, 9)), "new0", "new1"].sort(),
    );
    expect(paused.backlog).toBe(true);
    expect(ids(paused.cards).sort()).toEqual(ids(over.slice(0, 10)).sort());
  });

  it("in a backlog, puts the due cards earliest due first, equal due times in the order given", () => {
    const tied = card("tied");
    const last = latestFirst.at(-1);
    if (!last) throw new Error("no overdue card");
    const states = { ...overdueStates, [tied.id]: overdueStates[last.id] };

    const selected = selectQueue([...latestFirst, tied, ...fresh], states, today);

    expect(selected.backlog).toBe(true);
    expect(ids(selected.cards)).toEqual([earliestFirst[0], "tied", ...earliestFirst.slice(1)]);
    // An all-zero source keeps that order.
    expect(ids(orderQueue(selected, firstDraw))).toEqual(ids(selected.cards));
  });

  it("in a backlog, keeps each run of ten in its place in the order and shuffles it within", () => {
    expect(backlogBucketSize).toBe(10);
    const selected = selectQueue(latestFirst, overdueStates, today);
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
    const selected = selectQueue([...latestFirst, ...fresh], states, today);

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

describe("the study day", () => {
  const seoul = "Asia/Seoul";
  const losAngeles = "America/Los_Angeles";

  it("starts at 04:00 local time, so 03:59 belongs to the day before", () => {
    expect(studyDayStartHour).toBe(4);
    // 03:59 and 04:00 on 15 October in Seoul.
    const before = Date.UTC(2026, 9, 14, 18, 59);
    const at = Date.UTC(2026, 9, 14, 19);

    expect(studyDayStart(before, seoul)).toBe(Date.UTC(2026, 9, 13, 19));
    expect(studyDayStart(at, seoul)).toBe(at);
    // Control: in UTC both instants fall in the day that began at 04:00 UTC on the 14th.
    expect(studyDayStart(before, "UTC")).toBe(Date.UTC(2026, 9, 14, 4));
    expect(studyDayStart(at, "UTC")).toBe(Date.UTC(2026, 9, 14, 4));
  });

  it("runs from 04:00 to 04:00 local time across a change of offset", () => {
    // Clocks in Los Angeles go back from UTC-7 to UTC-8 at 09:00 UTC on 1 November 2026; at
    // 10:00 UTC it is 02:00 PST, still in the day of 31 October.
    const day = studyDay(Date.UTC(2026, 10, 1, 10), [], losAngeles, quota);

    expect(day.start).toBe(Date.UTC(2026, 9, 31, 11));
    expect(day.end).toBe(Date.UTC(2026, 10, 1, 12));
  });

  it("takes its new cards less those first answered in it, counting 04:00 and not 03:59", () => {
    // 11:00 on 15 October in Seoul; the day began at 19:00 UTC on the 14th.
    const at = Date.UTC(2026, 9, 15, 2);
    const firstAnswers = [
      Date.UTC(2026, 9, 14, 19),
      Date.UTC(2026, 9, 15),
      Date.UTC(2026, 9, 14, 18, 59),
    ];
    const day = studyDay(at, firstAnswers, seoul, quota);
    const cards = Array.from({ length: 30 }, (_, index) => card(`new${String(index)}`));

    expect(day.newCardsLeft).toBe(18);
    expect(selectQueue(cards, {}, day).cards).toHaveLength(18);
  });

  it("counts the same answers against the day in one time zone and not in another", () => {
    // 03:30 on 15 October in Seoul, 11:30 on 14 October in Los Angeles.
    const answered = [Date.UTC(2026, 9, 14, 18, 30)];
    // 11:00 in Seoul, 19:00 the day before in Los Angeles.
    const at = Date.UTC(2026, 9, 15, 2);

    expect(studyDay(at, answered, seoul, quota).newCardsLeft).toBe(20);
    expect(studyDay(at, answered, losAngeles, quota).newCardsLeft).toBe(19);
  });

  it("carries no unused quota to the next day, and does not count the day before's new cards", () => {
    const yesterday = Array.from({ length: 5 }, () => now - day);
    const cards = Array.from({ length: 50 }, (_, index) => card(`new${String(index)}`));
    const next = studyDay(now, yesterday, "UTC", quota);

    expect(next.newCardsLeft).toBe(20);
    expect(selectQueue(cards, {}, next).cards).toHaveLength(20);
  });

  it("never leaves fewer than zero cards once more than 20 new cards were answered", () => {
    const morning = Date.UTC(2026, 0, 15, 5);
    const over = studyDay(
      now,
      Array.from({ length: 25 }, () => morning),
      "UTC",
      quota,
    );

    expect(over.newCardsLeft).toBe(0);
    expect(selectQueue([card("new")], {}, over).cards).toEqual([]);
    // Control: with 19 answered, one new card is left.
    const fewer = studyDay(
      now,
      Array.from({ length: 19 }, () => morning),
      "UTC",
      quota,
    );
    expect(ids(selectQueue([card("new")], {}, fewer).cards)).toEqual(["new"]);
  });

  it("counts a card due later in the day, and not one due the next day", () => {
    const states: CardStates = {
      ["late" as CardId]: dueAfter(Date.UTC(2026, 0, 16, 3, 59), 1),
      ["tomorrow" as CardId]: dueAfter(Date.UTC(2026, 0, 16, 4), 1),
    };

    expect(ids(selectQueue([card("late"), card("tomorrow")], states, today).cards)).toEqual([
      "late",
    ]);
  });

  it("still pauses new cards in a backlog while the day has some left", () => {
    const [over, overStates] = reviewed(12, 10);

    expect(today.newCardsLeft).toBe(20);
    const newOf = (cards: readonly TestCard[]) =>
      ids(cards).filter((each) => each.startsWith("new"));
    expect(newOf(selectQueue([...over, ...fresh], overStates, today).cards)).toEqual([]);
    // Control: below the threshold the day takes both new cards.
    const [at, atStates] = reviewed(12, 9);
    expect(newOf(selectQueue([...at, ...fresh], atStates, today).cards)).toEqual(["new0", "new1"]);
  });

  it("counts study days in a row back from today, or from yesterday while today has no answer", () => {
    const at = (date: number, hours = 12) => Date.UTC(2026, 9, date, hours);
    const answers = [at(14), at(13), at(12, 5), at(10)];

    expect(streak(answers, at(14, 20), "UTC")).toBe(3);
    // Today not yet studied: the run up to yesterday still stands.
    expect(streak(answers.slice(1), at(14, 20), "UTC")).toBe(2);
    // An answer at 03:00 belongs to the day before.
    expect(streak([at(14), at(14, 3), at(12)], at(14, 20), "UTC")).toBe(3);
    // Control: a day with no answer ends the run.
    expect(streak(answers, at(16), "UTC")).toBe(0);
  });
});
