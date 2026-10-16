import "server-only";

import { cookies } from "next/headers";

import type { CardId } from "@/features/decks";
import { classifyFailure, requestTimeoutMs, type ServerFailure } from "@/lib/supabase/failure";
import { field, parseTime } from "@/lib/supabase/row";
import { pageSize, selectAll } from "@/lib/supabase/select-all";
import { createClient } from "@/lib/supabase/server";
import { readUserId } from "@/lib/supabase/session";
import { parseTimeZone, timeZoneCookie } from "@/lib/time-zone";

import type { Answer } from "./answer-write";
import { type StudyDay, studyDay, studyDayStart } from "./queue";

/** An answer stored in today's study day. Times are milliseconds since the epoch. */
export type TodayAnswer = {
  cardId: CardId;
  answer: Answer;
  reviewedAt: number;
  durationMs: number;
};

/**
 * Today's study day for the signed-in user: the day, with the new cards it has left, and every
 * answer stored in it, across every deck, oldest first. With [streak], also how many study days
 * in a row before today hold an answer, and whether any day before today holds one. The day is
 * read in the zone the browser names in its cookie, or `fallbackTimeZone` without one.
 */
export type Today = {
  day: StudyDay;
  answers: TodayAnswer[];
  streakBefore: number;
  answeredBefore: boolean;
};

/** How many card ids one request filters on, so its URL stays short. */
const idsPerRequest = 100;

/** Reads [Today], or a server failure, or `unreadable` for a row this version cannot read. */
export async function readToday(
  options: { streak: boolean } = { streak: false },
): Promise<{ today: Today } | { failure: ServerFailure | "unreadable" }> {
  const supabase = await createClient();
  const session = await readUserId(supabase);
  if ("failure" in session) return session;
  const timeZone = parseTimeZone(
    (await cookies()).getAll().find((cookie) => cookie.name === timeZoneCookie)?.value,
  );
  const now = Date.now();
  const start = studyDayStart(now, timeZone);
  const reviews = (columns: string, counted: boolean) =>
    supabase
      .from("reviews")
      .select(columns, counted ? { count: "exact" } : {})
      .eq("user_id", session.userId)
      .is("deleted_at", null);

  const [read, before] = await Promise.all([
    selectAll((from, to, counted) =>
      reviews("id, card_id, rating, reviewed_at, duration_ms", counted)
        .gte("reviewed_at", new Date(start).toISOString())
        .order("id")
        .range(from, to)
        .abortSignal(AbortSignal.timeout(requestTimeoutMs)),
    ),
    options.streak
      ? readStreakBefore(supabase, session.userId, start, timeZone)
      : { streak: 0, answered: false },
  ]);
  if ("failure" in read) return read;
  if ("failure" in before) return before;
  const answers: TodayAnswer[] = [];
  for (const row of read.rows) {
    const answer = parseAnswer(row);
    if (!answer) return { failure: "unreadable" };
    answers.push(answer);
  }
  answers.sort((a, b) => a.reviewedAt - b.reviewedAt);

  // A card answered today is new today unless it was also answered before.
  const ids = [...new Set(answers.map((answer) => answer.cardId))];
  const chunks: CardId[][] = [];
  for (let at = 0; at < ids.length; at += idsPerRequest) {
    chunks.push(ids.slice(at, at + idsPerRequest));
  }
  const earlier = await Promise.all(
    chunks.map((chunk) =>
      selectAll((from, to, counted) =>
        reviews("id, card_id", counted)
          .lt("reviewed_at", new Date(start).toISOString())
          .in("card_id", chunk)
          .order("id")
          .range(from, to)
          .abortSignal(AbortSignal.timeout(requestTimeoutMs)),
      ),
    ),
  );
  const answeredBefore = new Set<unknown>();
  for (const chunk of earlier) {
    if ("failure" in chunk) return chunk;
    for (const row of chunk.rows) answeredBefore.add(field(row, "card_id"));
  }
  const firstAnswers = new Map<CardId, number>();
  for (const answer of answers) {
    if (!answeredBefore.has(answer.cardId) && !firstAnswers.has(answer.cardId)) {
      firstAnswers.set(answer.cardId, answer.reviewedAt);
    }
  }
  return {
    today: {
      day: studyDay(now, firstAnswers.values(), timeZone),
      answers,
      streakBefore: before.streak,
      answeredBefore: before.answered,
    },
  };
}

/**
 * How many study days in a row end the day before [start] with an answer, read a page of the
 * latest answers at a time until a day without one, or the first answer, decides it; and
 * whether any answer is stored before [start].
 */
async function readStreakBefore(
  supabase: Awaited<ReturnType<typeof createClient>>,
  userId: string,
  start: number,
  timeZone: string,
): Promise<{ streak: number; answered: boolean } | { failure: ServerFailure | "unreadable" }> {
  let count = 0;
  let expected = studyDayStart(start - 1000, timeZone);
  for (let from = 0; ; from += pageSize) {
    const { data, error, status } = await supabase
      .from("reviews")
      .select("reviewed_at")
      .eq("user_id", userId)
      .is("deleted_at", null)
      .lt("reviewed_at", new Date(start).toISOString())
      .order("reviewed_at", { ascending: false })
      .range(from, from + pageSize - 1)
      .abortSignal(AbortSignal.timeout(requestTimeoutMs));
    if (error) return { failure: classifyFailure(error, status) };
    const answered = from > 0 || data.length > 0;
    for (const row of data) {
      const at = parseTime(field(row, "reviewed_at"));
      if (at === null) return { failure: "unreadable" };
      const day = studyDayStart(at, timeZone);
      if (day === expected) {
        count += 1;
        expected = studyDayStart(day - 1000, timeZone);
      } else if (day < expected) {
        return { streak: count, answered };
      }
    }
    if (data.length < pageSize) return { streak: count, answered };
  }
}

function parseAnswer(row: unknown): TodayAnswer | null {
  const cardId = field(row, "card_id");
  const rating = field(row, "rating");
  const reviewedAt = parseTime(field(row, "reviewed_at"));
  const durationMs = field(row, "duration_ms");
  if (typeof cardId !== "string" || reviewedAt === null || typeof durationMs !== "number") {
    return null;
  }
  const answer = rating === "good" ? "know" : rating === "again" ? "dontKnow" : null;
  if (!answer) return null;
  return { cardId: cardId as CardId, answer, reviewedAt, durationMs };
}
