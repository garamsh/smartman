import { describe, expect, it } from "vitest";

import type { CardId } from "@/features/decks";

import type { CardState } from "../queue";
import {
  bestStreak,
  heatLevel,
  masteredByWeek,
  masteredGain,
  periodStart,
  recallBands,
  type RecordAnswer,
  recordDays,
  retentionIn,
  retentionOver,
  share,
  studyDayCounts,
  targetRetention,
} from "../stats";

// The fixed histories of app/test/study/stats_test.dart, with the same instants and figures, so
// both clients count ADR 0037's metrics alike.

/** 09:00 UTC on Wednesday 14 October, five hours into the study day. */
const now = Date.UTC(2026, 9, 14, 9);
const day = 86_400_000;

const at = (month: number, date: number, hour = 9, minute = 0) =>
  Date.UTC(2026, month - 1, date, hour, minute);

function answer(card: string, know: boolean, reviewedAt: number): RecordAnswer {
  return { cardId: card as CardId, know, reviewedAt };
}

/** A state last reviewed at [lastReview] and due [days] days later. */
function state(lastReview: number, days: number): CardState {
  return { stability: 5, difficulty: 5, lastReview, due: lastReview + days * day };
}

describe("the retention", () => {
  it("counts each card's first answer of a study day after an earlier day, from 04:00, and not its first answer ever or a re-show", () => {
    const days = recordDays(
      [
        // Given out of order: the function orders them itself.
        answer("a", true, at(10, 12)),
        // A card's first answer ever is not scheduled.
        answer("a", false, at(10, 10)),
        answer("b", true, at(10, 10)),
        answer("b", false, at(10, 12, 10)),
        // A re-show after 모른다 on the same day is not scheduled.
        answer("b", true, at(10, 12, 10, 5)),
        // 03:59 is the end of 11 October's study day, so 04:00 is a later one and scheduled.
        answer("c", false, at(10, 12, 3, 59)),
        answer("c", true, at(10, 12, 4)),
        // Control: from 04:00 to 05:00 is one study day, so not scheduled.
        answer("d", false, at(10, 12, 4)),
        answer("d", true, at(10, 12, 5)),
      ],
      "UTC",
    );

    expect(days).toEqual([
      { dayStart: at(10, 10, 4), cards: 2, reviews: 0, known: 0 },
      { dayStart: at(10, 11, 4), cards: 1, reviews: 0, known: 0 },
      { dayStart: at(10, 12, 4), cards: 4, reviews: 3, known: 2 },
    ]);
  });

  it("over a period is its days' known reviews over their reviews, with its gap to the 90% target", () => {
    const days = recordDays(
      [
        ...["a", "b", "c", "d", "e"].map((card) => answer(card, true, at(10, 10))),
        ...["a", "b", "c"].map((card) => answer(card, true, at(10, 11))),
        answer("d", false, at(10, 11)),
        answer("e", true, at(10, 12)),
      ],
      "UTC",
    );
    const total = retentionOver(days);

    expect(targetRetention).toBe(0.9);
    expect(total).toEqual({ reviews: 5, known: 4 });
    expect(share(total ?? { reviews: 1, known: 0 })).toBeCloseTo(0.8, 12);
    expect(share(total ?? { reviews: 1, known: 0 }) - targetRetention).toBeCloseTo(-0.1, 12);
    expect(retentionOver([])).toBeNull();
  });

  it("over 7 and 30 days starts at 04:00 on the 7th and the 30th study day back, today included, every day has no start, and only days with a scheduled review are shown", () => {
    expect(periodStart("week", now, "UTC")).toBe(at(10, 8, 4));
    expect(periodStart("month", now, "UTC")).toBe(at(9, 15, 4));
    expect(periodStart("all", now, "UTC")).toBeNull();

    const days = recordDays(
      [
        answer("a", true, at(10, 1)),
        // 03:59 on 8 October ends 7 October's study day, before the week.
        answer("a", true, at(10, 8, 3, 59)),
        answer("b", true, at(10, 1)),
        // Control: 04:00 starts the week's first study day.
        answer("b", false, at(10, 8, 4)),
      ],
      "UTC",
    );

    expect(retentionIn(days, "week", now, "UTC").map((entry) => entry.dayStart)).toEqual([
      at(10, 8, 4),
    ]);
    // Every day is 7 October's and 8 October's: 1 October holds first answers alone.
    expect(retentionIn(days, "all", now, "UTC").map((entry) => entry.dayStart)).toEqual([
      at(10, 7, 4),
      at(10, 8, 4),
    ]);
  });
});

describe("the recall bands", () => {
  it("split cards at 0.95 and 0.8, each bound in the upper band, with the mean", () => {
    const bands = recallBands([1, 0.95, 0.9499, 0.8, 0.7999]);

    expect([bands.strong, bands.fair, bands.fading]).toEqual([2, 2, 1]);
    expect(bands.mean).toBeCloseTo((1 + 0.95 + 0.9499 + 0.8 + 0.7999) / 5, 12);
    expect(recallBands([]).mean).toBeNull();
  });
});

describe("the mastered weeks", () => {
  it("count the cards mastered at the end of each of the last eight weeks, each week ending at 04:00", () => {
    // The weeks end at 04:00 on 27 August, 3, 10, 17 and 24 September, and 1, 8 and 15 October.
    const weeks = masteredByWeek(
      [
        // Learning, then mastered by a review at 03:59 on 8 October.
        [state(at(9, 1), 2), state(at(10, 8, 3, 59), 30)],
        // Control: mastered at 04:00 on 8 October, in the week after.
        [state(at(10, 8, 4), 30)],
        // Mastered on 10 September after 04:00, then forgotten on 10 October.
        [state(at(9, 10, 5), 25), state(at(10, 10), 1)],
        // Never mastered.
        [state(at(9, 1), 20)],
      ],
      now,
      "UTC",
    );

    expect(weeks).toEqual([0, 0, 0, 1, 1, 1, 2, 2]);
  });

  it("gain this week's count less the count four weeks before, and none unless more", () => {
    expect(masteredGain([0, 1, 2, 3, 5, 6, 7, 9])).toBe(6);
    expect(masteredGain([0, 0, 0, 4, 4, 4, 4, 4])).toBeNull();
    expect(masteredGain([0, 0, 0, 5, 4, 4, 4, 4])).toBeNull();
  });
});

describe("the study days", () => {
  it("count the distinct cards answered on each of the last 84 study days, from 04:00 in the device's zone", () => {
    // Seoul's 04:00 on 14 October is 19:00 UTC on 13 October.
    const days = recordDays(
      [
        answer("a", true, at(10, 13, 18, 59)),
        answer("a", true, at(10, 13, 19)),
        // The same card twice in a day is one card.
        answer("a", false, at(10, 13, 20)),
        answer("b", true, at(10, 13, 21)),
        // 03:59 on 23 July in Seoul ends 22 July's study day, outside the twelve weeks; 04:00
        // starts the first of the 84 days.
        answer("c", true, at(7, 22, 18, 59)),
        answer("d", true, at(7, 22, 19)),
      ],
      "Asia/Seoul",
    );
    const counts = studyDayCounts(days, now, "Asia/Seoul");

    expect(counts).toHaveLength(84);
    expect(counts[0]).toEqual({ date: Date.UTC(2026, 6, 23), cards: 1 });
    expect(counts[82]).toEqual({ date: Date.UTC(2026, 9, 13), cards: 1 });
    expect(counts[83]).toEqual({ date: Date.UTC(2026, 9, 14), cards: 2 });
    expect(counts.reduce((sum, entry) => sum + entry.cards, 0)).toBe(4);
  });

  it("level a cell 0 without a card, then 1 to 3 by the third of the busiest day it falls in", () => {
    expect([0, 1, 4, 5, 8, 9, 12].map((cards) => heatLevel(cards, 12))).toEqual([
      0, 1, 1, 2, 2, 3, 3,
    ]);
    expect(heatLevel(1, 1)).toBe(3);
  });

  it("give the best streak as the longest run of study days with an answer, from 04:00", () => {
    const best = bestStreak(
      [
        at(10, 1),
        at(10, 2),
        at(10, 3),
        // 03:59 on 5 October ends 4 October's study day: a fourth day in a row.
        at(10, 5, 3, 59),
        // Control: after a gap, a run of two.
        at(10, 9, 4),
        at(10, 10),
      ],
      "UTC",
    );

    expect(best).toBe(4);
    expect(bestStreak([], "UTC")).toBe(0);
  });
});
