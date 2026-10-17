// @vitest-environment node
import { readFileSync } from "node:fs";
import path from "node:path";

import { describe, expect, it } from "vitest";

import type { CardId } from "@/features/decks";

import {
  dailyGoal,
  deckProgress,
  forecast,
  forecastDays,
  masteredIntervalDays,
  progressOf,
  statusLine,
  todayStatus,
} from "../overview";
import { studyDay } from "../queue";

// The cases of app/test/study/overview_test.dart, so the two clients define the same figures.

const day = 86_400_000;
/** 09:00 UTC on 14 October 2026, five hours into the study day in UTC. */
const now = Date.UTC(2026, 9, 14, 9);
const today = studyDay(now, [], "UTC");
const id = (value: string) => value as CardId;

describe("a card's progress", () => {
  it("is mastered from an interval of 21 days, learning below it, and new without a review", () => {
    const at = now - 30 * day;
    expect(progressOf({ stability: 1, difficulty: 5, lastReview: at, due: at + 21 * day })).toBe(
      "mastered",
    );
    expect(
      progressOf({ stability: 1, difficulty: 5, lastReview: at, due: at + 21 * day - 1000 }),
    ).toBe("learning");
    expect(progressOf(undefined)).toBe("fresh");
  });

  it("counts a deck's cards by progress, each once", () => {
    const at = now - 30 * day;
    expect(
      deckProgress([{ id: id("a") }, { id: id("b") }, { id: id("c") }], {
        [id("a")]: { stability: 1, difficulty: 5, lastReview: at, due: at + 30 * day },
        [id("b")]: { stability: 1, difficulty: 5, lastReview: at, due: at + 2 * day },
      }),
    ).toEqual({ mastered: 1, learning: 1, fresh: 1 });
  });
});

describe("the forecast", () => {
  it("is today's load, then the cards due within each later day, from 04:00 to 04:00", () => {
    const tomorrow = Date.UTC(2026, 9, 15, 4);
    const states = [
      // 03:59 on the 15th belongs to today, which the load already counts.
      { stability: 1, difficulty: 5, lastReview: now, due: tomorrow - 60_000 },
      // 04:00 on the 15th is tomorrow's.
      { stability: 1, difficulty: 5, lastReview: now, due: tomorrow },
      // Past the seventh day: counted on none.
      { stability: 1, difficulty: 5, lastReview: now, due: tomorrow + 6 * day },
    ];
    expect(forecast(states, today, 9, "UTC")).toEqual([9, 1, 0, 0, 0, 0, 0]);
  });
});

describe("the daily goal", () => {
  it("is the cards answered today and those left, each once; done are those no longer left", () => {
    const answers = [
      { cardId: id("a"), reviewedAt: today.start + 1000 },
      { cardId: id("a"), reviewedAt: today.start + 2000 },
      { cardId: id("b"), reviewedAt: today.start + 3000 },
      // Yesterday's answer is no part of today's goal.
      { cardId: id("z"), reviewedAt: today.start - 1000 },
    ];
    // b was answered "모른다" and is due again today: left, not done.
    expect(dailyGoal(answers, [id("b"), id("c")], today)).toEqual({ done: 1, goal: 3 });
  });
});

describe("today's status", () => {
  const status = (done: number, goal: number, streak = 0) =>
    statusLine(todayStatus({ done, goal }, streak));

  it("states a streak of two days or more with nothing done, and otherwise waits", () => {
    expect(status(0, 10, 2)).toBe("2일째 이어 가는 중이에요");
    expect(status(0, 10, 1)).toBe("오늘의 첫 카드를 기다리고 있어요");
    expect(status(0, 3, 1)).toBe("오늘의 첫 카드를 기다리고 있어요");
  });

  it("is almost done with three cards or fewer left, not with four", () => {
    expect(status(7, 10)).toBe("거의 다 왔어요");
    expect(status(6, 10)).toBe("절반을 넘었어요");
  });

  it("is past half at exactly half, and a good start one short of it", () => {
    expect(status(10, 20)).toBe("절반을 넘었어요");
    expect(status(9, 20)).toBe("좋은 출발이에요");
  });
});

describe("the overview's constants", () => {
  it("are app/lib/study/src/overview.dart's", () => {
    const root = path.join(import.meta.dirname, "../../../../..");
    const dart = readFileSync(path.join(root, "app/lib/study/src/overview.dart"), "utf8");
    expect(/^const forecastDays = (\d+);$/m.exec(dart)?.[1]).toBe(String(forecastDays));
    expect(/^const masteredInterval = Duration\(days: (\d+)\);$/m.exec(dart)?.[1]).toBe(
      String(masteredIntervalDays),
    );
  });
});
