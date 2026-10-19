// @vitest-environment node
import { readFileSync } from "node:fs";
import path from "node:path";

import { describe, expect, it } from "vitest";

import type { CardId } from "@/features/decks";

import {
  deckProgress,
  catchUp,
  chartDays,
  masteredIntervalDays,
  progressOf,
  statusLine,
  todayStatus,
  nextReviewOf,
} from "../overview";
import { studyDay } from "../queue";

// The cases of app/test/study/overview_test.dart, so the two clients define the same figures.

const day = 86_400_000;
/** 09:00 UTC on 14 October 2026, five hours into the study day in UTC. */
const now = Date.UTC(2026, 9, 14, 9);
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

describe("the next review", () => {
  const due = (at: number) => ({ stability: 1, difficulty: 5, lastReview: at - day, due: at });
  const today = studyDay(now, [], "UTC", 20);

  it("is the first later day with a card due, each day from 04:00 to 04:00", () => {
    expect(
      nextReviewOf(
        [
          // Due today, before the day ends: not a later day's.
          due(Date.UTC(2026, 9, 15, 3, 59)),
          // 04:00 starts tomorrow's study day.
          due(Date.UTC(2026, 9, 15, 4)),
          due(Date.UTC(2026, 9, 16, 3, 59)),
          due(Date.UTC(2026, 9, 16, 4)),
        ],
        today,
        "UTC",
      ),
    ).toEqual({ after: 1, cards: 2 });
    // The last of the seven days ends at 04:00 on 21 October.
    expect(nextReviewOf([due(Date.UTC(2026, 9, 21, 3, 59))], today, "UTC")).toEqual({
      after: 6,
      cards: 1,
    });
    expect(
      nextReviewOf(
        [due(Date.UTC(2026, 9, 15, 3, 59)), due(Date.UTC(2026, 9, 21, 4))],
        today,
        "UTC",
      ),
    ).toBeNull();
  });

  it("follows 04:00 local time across a change of offset", () => {
    // 11:00 on 31 October 2025 in Los Angeles; 03:00 and 03:59 on 2 November, at UTC-8 after the
    // change, are still 1 November's.
    const before = studyDay(Date.UTC(2025, 9, 31, 18), [], "America/Los_Angeles", 20);
    expect(
      nextReviewOf(
        [due(Date.UTC(2025, 10, 2, 11)), due(Date.UTC(2025, 10, 2, 11, 59))],
        before,
        "America/Los_Angeles",
      ),
    ).toEqual({ after: 1, cards: 2 });
  });
});

describe("the catch-up", () => {
  it("falls by the pace each day, to zero and not below", () => {
    expect(catchUp(84, 30)).toEqual([84, 54, 24, 0, 0, 0, 0]);
    // Control: a pace of one keeps a backlog of seven on every day.
    expect(catchUp(7, 1)).toEqual([7, 6, 5, 4, 3, 2, 1]);
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
    expect(/^const chartDays = (\d+);$/m.exec(dart)?.[1]).toBe(String(chartDays));
    expect(/^const masteredInterval = Duration\(days: (\d+)\);$/m.exec(dart)?.[1]).toBe(
      String(masteredIntervalDays),
    );
  });
});
