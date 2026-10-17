import { describe, expect, it } from "vitest";

import { coldStartNewCards, coldStartStudyDays } from "../queue";
import {
  dailyNewCards,
  paceOf,
  sessionMinutes,
  type StudyDayTotal,
  studyTime,
} from "../study-time";

// The fixed histories below are the same as those of app/test/study/study_time_test.dart, with
// the same expected figures, so the two clients compute the same figure from the same history.

/** A study day of [reviews] reviews at [reviewMs] each and [firsts] first answers at [firstMs] each. */
function studyDay({
  reviews = 20,
  reviewMs = 4000,
  firsts = 20,
  firstMs = 8000,
}: { reviews?: number; reviewMs?: number; firsts?: number; firstMs?: number } = {}): StudyDayTotal {
  return {
    reviewMs: reviews * reviewMs,
    reviews,
    firstMs: firsts * firstMs,
    firstAnswers: firsts,
  };
}

/** Ten study days of 4 minutes: 20 reviews at 4 s and 20 first answers at 8 s. */
const steady = Array.from({ length: 10 }, () => studyDay());

describe("the figure", () => {
  it("sets aside a steady history's reviews at the review pace and fills the rest of its study time with new cards at the first-answer pace", () => {
    expect(studyTime(steady)).toBe(240000);
    expect(paceOf(steady)).toEqual({ reviewMs: 4000, firstMs: 8000 });
    // (240 s - 30 reviews at 4 s) / 8 s.
    expect(dailyNewCards(steady, { due: 30, load: 30 })).toBe(15);
  });

  it("lets reviews due beyond the daily load crowd out new cards, spread over a week, down to none", () => {
    expect(dailyNewCards(steady, { due: 30, load: 30 })).toBe(15);
    // 30 + 30 / 7 reviews set aside: (240 - 137.1) s / 8 s.
    expect(dailyNewCards(steady, { due: 60, load: 30 })).toBe(12);
    expect(dailyNewCards(steady, { due: 90, load: 30 })).toBe(10);
    // The daily load alone fills the study time, and more leaves none.
    expect(dailyNewCards(steady, { due: 60, load: 60 })).toBe(0);
    expect(dailyNewCards(steady, { due: 100, load: 70 })).toBe(0);
    // Fewer due than the daily load set aside the load.
    expect(dailyNewCards(steady, { due: 0, load: 30 })).toBe(15);
  });

  it("takes 20 new cards in a cold start until the window holds five study days", () => {
    expect(coldStartNewCards).toBe(20);
    expect(coldStartStudyDays).toBe(5);
    expect(dailyNewCards(steady.slice(0, 4), { due: 0, load: 0 })).toBe(20);
    expect(dailyNewCards([], { due: 0, load: 0 })).toBe(20);
    // Control: from five study days the figure is the user's own.
    expect(dailyNewCards(steady.slice(0, 5), { due: 30, load: 30 })).toBe(15);
  });

  it("moves the study time at most 10% from one study day to the next", () => {
    // A day of 10 minutes after ten of 4: 50 reviews and 50 first answers.
    const jump = [...steady, studyDay({ reviews: 50, firsts: 50 })];

    expect(studyTime(steady)).toBe(240000);
    expect(studyTime(jump)).toBe(264000);
    // (264 s - 120 s) / 8 s.
    expect(dailyNewCards(jump, { due: 30, load: 30 })).toBe(18);
  });

  it("lets a recent long week outweigh an older short month in the study time", () => {
    // 23 study days of 2 minutes, then 7 of 4.
    const days = [
      ...Array.from({ length: 23 }, () => studyDay({ reviews: 10, firsts: 10 })),
      ...Array.from({ length: 7 }, () => studyDay()),
    ];
    const plainMean = (23 * 120000 + 7 * 240000) / 30;

    expect(plainMean).toBe(148000);
    // Nearer the week's 4 minutes than the month's 2.
    expect(studyTime(days)).toBeGreaterThan(180000);
  });

  it("lets a recent fast week pull the review pace below the plain mean of the window", () => {
    // 23 study days of reviews at 8 s, then 7 at 4 s, ten reviews each.
    const days = [
      ...Array.from({ length: 23 }, () => studyDay({ reviews: 10, reviewMs: 8000 })),
      ...Array.from({ length: 7 }, () => studyDay({ reviews: 10 })),
    ];
    const plainMean = (23 * 8000 + 7 * 4000) / 30;

    expect(paceOf(days).reviewMs).toBeLessThan(plainMean - 500);
  });

  it("takes a kind with fewer than 20 answers in the window at 10 s an answer", () => {
    expect(paceOf([studyDay({ reviews: 19, firsts: 20 })])).toEqual({
      reviewMs: 10000,
      firstMs: 8000,
    });
  });

  it("counts a session's minutes from its reviews at the review pace and its new cards at the first-answer pace, rounded up", () => {
    // 30 reviews at 4 s and 15 new cards at 8 s: 4 minutes.
    expect(sessionMinutes(30, 15, { reviewMs: 4000, firstMs: 8000 })).toBe(4);
    expect(sessionMinutes(30, 16, { reviewMs: 4000, firstMs: 8000 })).toBe(5);
  });
});
