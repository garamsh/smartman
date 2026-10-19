import "server-only";

import { cookies } from "next/headers";

import { classifyFailure, requestTimeoutMs, type ServerFailure } from "@/supabase/failure";
import { field, parseTime } from "@/supabase/row";
import { createClient } from "@/supabase/server";
import { readUserId } from "@/supabase/session";

import { type FoldedAnswer, foldStates, recallAt } from "./engine-server";
import { type CardState, streak } from "./queue";
import {
  bestStreak,
  retentionIn,
  masteredByWeek,
  type RecallBands,
  recallBands,
  type RecordDay,
  type StudyDayCount,
  studyDayCounts,
} from "./stats";
import { parseTimeZone, timeZoneCookie } from "./time-zone";

/**
 * What the 기록 page shows, read at [now] in [timeZone] (ADR 0037, ADR 0047): every study day
 * with an answer, the recall bands of the decks' cards now, the mastered cards at the end of each
 * of the last eight weeks, the last twelve weeks of study days, and the current and best streaks.
 */
export type StudyRecord = {
  now: number;
  timeZone: string;
  days: RecordDay[];
  recall: RecallBands;
  mastered: number[];
  studyDays: StudyDayCount[];
  streak: number;
  bestStreak: number;
};

/** A live card of a live deck with an answer, as `study_record_cards` returns it. */
type RecordCard = { state: CardState | null; answers: FoldedAnswer[] };

/**
 * Reads the signed-in user's [StudyRecord] in two requests sent together, `study_record_days` and
 * `study_record_cards`, and folds the cards' answers through the engine on the server; or a
 * server failure, or `unreadable` for a row this version cannot read or a state the engine
 * refuses. The day is read in the zone the browser names in its cookie, or `fallbackTimeZone`.
 */
export async function readRecord(): Promise<
  { record: StudyRecord } | { failure: ServerFailure | "unreadable" }
> {
  const supabase = await createClient();
  const session = await readUserId(supabase);
  if ("failure" in session) return session;
  const timeZone = parseTimeZone(
    (await cookies()).getAll().find((cookie) => cookie.name === timeZoneCookie)?.value,
  );
  const now = Date.now();
  const [daysRead, cardsRead] = await Promise.all([
    supabase
      .rpc("study_record_days", { time_zone: timeZone, before: new Date(now).toISOString() })
      .abortSignal(AbortSignal.timeout(requestTimeoutMs)),
    supabase.rpc("study_record_cards").abortSignal(AbortSignal.timeout(requestTimeoutMs)),
  ]);
  if (daysRead.error) return { failure: classifyFailure(daysRead.error, daysRead.status) };
  if (cardsRead.error) return { failure: classifyFailure(cardsRead.error, cardsRead.status) };
  const days = parseRows(daysRead.data, parseDay);
  const cards = parseRows(cardsRead.data, parseCard);
  if (!days || !cards) return { failure: "unreadable" };

  const recalls: number[] = [];
  const histories: CardState[][] = [];
  for (const card of cards) {
    if (card.state) {
      const recall = await recallAt(card.state, now);
      if ("error" in recall) return { failure: "unreadable" };
      recalls.push(recall.recall);
    }
    const folded = await foldStates(card.answers);
    if ("error" in folded) return { failure: "unreadable" };
    histories.push(folded.states);
  }
  const starts = days.map((day) => day.dayStart);
  return {
    record: {
      now,
      timeZone,
      days,
      recall: recallBands(recalls),
      mastered: masteredByWeek(histories, now, timeZone),
      studyDays: studyDayCounts(days, now, timeZone),
      streak: streak(starts, now, timeZone),
      bestStreak: bestStreak(starts, timeZone),
    },
  };
}

/** Each of [rows] parsed by [parse], or null when they are not an array or one does not parse. */
function parseRows<T>(rows: unknown, parse: (row: unknown) => T | null): T[] | null {
  if (!Array.isArray(rows)) return null;
  const parsed: T[] = [];
  for (const row of rows) {
    const value = parse(row);
    if (value === null) return null;
    parsed.push(value);
  }
  return parsed;
}

function parseDay(row: unknown): RecordDay | null {
  const dayStart = parseTime(field(row, "day_start"));
  const cards = count(field(row, "cards"));
  const reviews = count(field(row, "reviews"));
  const known = count(field(row, "known"));
  if (dayStart === null || cards === null || reviews === null || known === null) return null;
  if (known > reviews) return null;
  return { dayStart, cards, reviews, known };
}

function parseCard(row: unknown): RecordCard | null {
  const ratings = field(row, "ratings");
  const times = field(row, "reviewed_at");
  const factors = field(row, "fuzz_factors");
  if (!Array.isArray(ratings) || !Array.isArray(times) || !Array.isArray(factors)) return null;
  if (
    ratings.length === 0 ||
    times.length !== ratings.length ||
    factors.length !== ratings.length
  ) {
    return null;
  }
  const answers: FoldedAnswer[] = [];
  for (const [index, rating] of ratings.entries()) {
    const reviewedAt = parseTime(times[index]);
    const fuzzFactor: unknown = factors[index];
    if (rating !== "good" && rating !== "again") return null;
    if (reviewedAt === null) return null;
    if (
      fuzzFactor !== null &&
      (typeof fuzzFactor !== "number" || fuzzFactor < 0 || fuzzFactor >= 1)
    ) {
      return null;
    }
    answers.push({ know: rating === "good", reviewedAt, fuzzFactor });
  }
  const state = parseState(row);
  if (state === undefined) return null;
  return { state, answers };
}

/** The card's stored state, null when it has none, or undefined when its columns do not parse. */
function parseState(row: unknown): CardState | null | undefined {
  const stability = field(row, "stability");
  const difficulty = field(row, "difficulty");
  const lastReview = field(row, "last_review");
  const due = field(row, "due");
  if (stability === null && difficulty === null && lastReview === null && due === null) {
    return null;
  }
  const lastReviewAt = parseTime(lastReview);
  const dueAt = parseTime(due);
  if (typeof stability !== "number" || typeof difficulty !== "number") return undefined;
  if (lastReviewAt === null || dueAt === null) return undefined;
  return { stability, difficulty, lastReview: lastReviewAt, due: dueAt };
}

/** [value] when it is a whole number at least zero, or null. */
function count(value: unknown): number | null {
  return typeof value === "number" && Number.isInteger(value) && value >= 0 ? value : null;
}

/**
 * The signed-in user's study days with a scheduled review over the last 30 study days, for the
 * 오늘 page's retention card, and every study day as read, which its last seven days count: one
 * request, `study_record_days`, and no engine; or a server failure, or `unreadable` for a row this
 * version cannot read.
 */
export async function readRecentRetention(): Promise<
  | { days: RecordDay[]; studyDays: RecordDay[]; timeZone: string }
  | { failure: ServerFailure | "unreadable" }
> {
  const supabase = await createClient();
  const session = await readUserId(supabase);
  if ("failure" in session) return session;
  const timeZone = parseTimeZone(
    (await cookies()).getAll().find((cookie) => cookie.name === timeZoneCookie)?.value,
  );
  const now = Date.now();
  const read = await supabase
    .rpc("study_record_days", { time_zone: timeZone, before: new Date(now).toISOString() })
    .abortSignal(AbortSignal.timeout(requestTimeoutMs));
  if (read.error) return { failure: classifyFailure(read.error, read.status) };
  const days = parseRows(read.data, parseDay);
  if (!days) return { failure: "unreadable" };
  return { days: retentionIn(days, "month", now, timeZone), studyDays: days, timeZone };
}
