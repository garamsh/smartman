import { describe, expect, it } from "vitest";

import { dailyMinuteStep, defaultDailyMinutes, maxDailyMinutes, minDailyMinutes } from "../queue";
import {
  dailyNewCards,
  daysToStartAll,
  type MinutesPlan,
  minutesPreview,
  paceOf,
  sessionMinutes,
  type StudyDayTotal,
  unknownPace,
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
  it("fills the daily minutes left after the due reviews with new cards, the reviews at the review pace and the new cards at the first-answer pace", () => {
    const pace = paceOf(steady);
    expect(pace).toEqual({ reviewMs: 4000, firstMs: 8000 });
    // (20 min - 30 reviews at 4 s) / 8 s.
    expect(dailyNewCards({ minutes: 20, due: 30, pace })).toBe(135);
    // (4 min - 30 reviews at 4 s) / 8 s.
    expect(dailyNewCards({ minutes: 4, due: 30, pace })).toBe(15);
    expect(dailyNewCards({ minutes: 4, due: 0, pace })).toBe(30);
  });

  it("lets due reviews crowd out new cards, down to none and never below", () => {
    const pace = paceOf(steady);
    // 60 reviews at 4 s fill 4 minutes; more leave none.
    expect(dailyNewCards({ minutes: 4, due: 60, pace })).toBe(0);
    expect(dailyNewCards({ minutes: 4, due: 100, pace })).toBe(0);
    // Control: one review fewer leaves room for half a card, rounded down.
    expect(dailyNewCards({ minutes: 4, due: 59, pace })).toBe(0);
    expect(dailyNewCards({ minutes: 4, due: 58, pace })).toBe(1);
  });

  it("defaults to 20 minutes, offers 5 to 180 in steps of 5, and takes every answer at 10 s with no history", () => {
    expect(defaultDailyMinutes).toBe(20);
    expect(dailyMinuteStep).toBe(5);
    expect([minDailyMinutes, maxDailyMinutes]).toEqual([5, 180]);
    expect(paceOf([])).toEqual(unknownPace);
    // 20 minutes of 10 s answers, from the first day: no cold start.
    expect(dailyNewCards({ minutes: defaultDailyMinutes, due: 0, pace: unknownPace })).toBe(120);
  });

  it("counts the days after today until the new cards are all started: none when today takes them all, by the daily figure after, and never with none a day", () => {
    const days = (remaining: number, today: number, perDay: number) =>
      daysToStartAll({ remaining, today, perDay });

    expect(days(10, 15, 15)).toBe(0);
    expect(days(15, 15, 15)).toBe(0);
    // 85 left after today, 15 a day: six more days.
    expect(days(100, 15, 15)).toBe(6);
    expect(days(16, 15, 15)).toBe(1);
    // 30 left after today, 15 a day: exactly two more days.
    expect(days(45, 15, 15)).toBe(2);
    // Control: none a day after today never takes them all.
    expect(days(16, 15, 0)).toBeNull();
    expect(days(15, 15, 0)).toBe(0);
  });

  it("lets a recent fast week outweigh an older slow month in the review pace", () => {
    // 23 study days of reviews at 8 s, then 7 at 4 s, ten reviews each.
    const days = [
      ...Array.from({ length: 23 }, () => studyDay({ reviews: 10, reviewMs: 8000 })),
      ...Array.from({ length: 7 }, () => studyDay({ reviews: 10 })),
    ];

    // Nearer the week's 4 s than the month's 8.
    expect(paceOf(days).reviewMs).toBeLessThan(6000);
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

// The same plans as app/test/study/daily_minutes_test.dart, with the same figures.
describe("what a choice of minutes means", () => {
  const plan = (fields: Partial<MinutesPlan> & { unstarted: number }): MinutesPlan => ({
    due: 0,
    started: 0,
    backlog: false,
    pace: unknownPace,
    ...fields,
  });

  it("takes today the new cards the minutes leave room for, less those started today", () => {
    // 20 min at 10 s: 120 a day, of which 20 were started today; 400 left after today: four more days.
    expect(minutesPreview(plan({ started: 20, unstarted: 500 }), 20)).toEqual({
      fresh: 100,
      after: 4,
    });
  });

  it("puts due reviews first, so a backlog of them leaves no new card", () => {
    // 60 due reviews at 10 s fill 10 minutes.
    expect(minutesPreview(plan({ due: 60, unstarted: 50 }), 10)).toEqual({
      fresh: 0,
      after: null,
    });
    // Control: five more minutes leave room for 30.
    expect(minutesPreview(plan({ due: 60, unstarted: 50 }), 15).fresh).toBe(30);
  });

  it("takes no new card in a backlog, whatever the minutes", () => {
    expect(minutesPreview(plan({ unstarted: 50, backlog: true }), 60)).toEqual({
      fresh: 0,
      after: null,
    });
  });

  it("takes no more than the cards left, and with none left counts no day", () => {
    expect(minutesPreview(plan({ unstarted: 7 }), 20)).toEqual({ fresh: 7, after: 0 });
    expect(minutesPreview(plan({ unstarted: 0 }), 20)).toEqual({ fresh: 0, after: null });
  });
});
