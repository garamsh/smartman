import type { CardId } from "@/features/decks";

import type { Random } from "./random";

// The queue rules of study.md, in one place: which cards a session studies, in what order, and
// when a "Don't know" comes back. The counts the deck screens show come from the same rules.

/** How many never-reviewed cards a study day takes, across all the user's decks. */
export const newCardLimit = 20;

/** The local hour a study day starts at. */
export const studyDayStartHour = 4;

/** The fewest other cards shown before a "Don't know" card comes back. */
export const reshowGapMin = 3;

/** The most other cards shown before a "Don't know" card comes back. */
export const reshowGapMax = 5;

/**
 * The cards are in backlog when more than this many days of reviews are due: the due count
 * against this multiple of `dailyLoad`.
 */
export const backlogDays = 3;

/** How many consecutive cards of a backlog's order are shuffled together. */
export const backlogBucketSize = 10;

/** A day, in milliseconds. */
const day = 86_400_000;

/** A reviewed card's stored scheduling state. Times are milliseconds since the epoch. */
export type CardState = {
  stability: number;
  difficulty: number;
  lastReview: number;
  due: number;
};

/** The stored state of each reviewed card; a card never reviewed has none. */
export type CardStates = Partial<Record<CardId, CardState>>;

/** Today's study day as the queue reads it. Times are milliseconds since the epoch. */
export type StudyDay = {
  start: number;
  /** When the next study day starts. */
  end: number;
  /** How many new cards the day still takes: [newCardLimit] less those first answered in it. */
  newCardsLeft: number;
};

const formats = new Map<string, Intl.DateTimeFormat>();

/** The wall-clock time in [timeZone] at [instant], as if it were UTC. */
function wallClock(instant: number, timeZone: string): number {
  let format = formats.get(timeZone);
  if (!format) {
    format = new Intl.DateTimeFormat("en-US", {
      timeZone,
      hourCycle: "h23",
      year: "numeric",
      month: "numeric",
      day: "numeric",
      hour: "numeric",
      minute: "numeric",
      second: "numeric",
    });
    formats.set(timeZone, format);
  }
  const part = (type: Intl.DateTimeFormatPartTypes) =>
    Number(format.formatToParts(instant).find((entry) => entry.type === type)?.value);
  return Date.UTC(
    part("year"),
    part("month") - 1,
    part("day"),
    part("hour"),
    part("minute"),
    part("second"),
  );
}

/** The offset from UTC of [timeZone] at [instant], in milliseconds, to the second. */
function offsetAt(instant: number, timeZone: string): number {
  return wallClock(instant, timeZone) - Math.floor(instant / 1000) * 1000;
}

/**
 * The [studyDayStartHour] o'clock of the calendar date [year]-[month]-[date] in [timeZone], read
 * again at the instant it names so that a change of offset since that date's midnight applies.
 * Out-of-range dates roll over as `Date.UTC` rolls them.
 */
function startOn(year: number, month: number, date: number, timeZone: string): number {
  const wall = Date.UTC(year, month, date, studyDayStartHour);
  return wall - offsetAt(wall - offsetAt(wall, timeZone), timeZone);
}

/** When the study day holding [now] started: the latest 04:00 at or before it in [timeZone]. */
export function studyDayStart(now: number, timeZone: string): number {
  const wall = new Date(wallClock(now, timeZone));
  const back = wall.getUTCHours() < studyDayStartHour ? 1 : 0;
  return startOn(wall.getUTCFullYear(), wall.getUTCMonth(), wall.getUTCDate() - back, timeZone);
}

/**
 * The study day holding [now] in [timeZone], in which the user first answered a card at each
 * of [firstAnswers], across every deck.
 */
export function studyDay(now: number, firstAnswers: Iterable<number>, timeZone: string): StudyDay {
  const start = studyDayStart(now, timeZone);
  const wall = new Date(wallClock(start, timeZone));
  const end = startOn(wall.getUTCFullYear(), wall.getUTCMonth(), wall.getUTCDate() + 1, timeZone);
  let taken = 0;
  for (const answer of firstAnswers) if (answer >= start && answer < end) taken += 1;
  return { start, end, newCardsLeft: Math.max(0, newCardLimit - taken) };
}

/**
 * How many study days in a row in [timeZone] hold one of [answers]: counted back from the day
 * holding [now] when it holds one, otherwise from the day before, so a day not yet studied
 * breaks nothing until it ends.
 */
export function streak(answers: Iterable<number>, now: number, timeZone: string): number {
  const days = new Set<number>();
  for (const answer of answers) days.add(studyDayStart(answer, timeZone));
  const before = (day: number) => studyDayStart(day - 1000, timeZone);
  let day = studyDayStart(now, timeZone);
  if (!days.has(day)) day = before(day);
  let count = 0;
  while (days.has(day)) {
    count += 1;
    day = before(day);
  }
  return count;
}

/**
 * What a session over some cards would study today. In a backlog, `fresh` is 0: new cards pause
 * until the reviews are done.
 */
export type TodayCount = { review: number; fresh: number; backlog: boolean };

/**
 * The cards a session studies. In a backlog: every due card, earliest due first, and no new
 * card. Otherwise: every due card, then as many new ones as the day has left, oldest first.
 */
export type SelectedQueue<C> = { cards: C[]; backlog: boolean };

type Queueable = { id: CardId; createdAt: number };

/**
 * The reviews a day [states] ask for at their current intervals: the sum, over every reviewed
 * card, of one over its interval in days, at least one.
 */
export function dailyLoad(states: Iterable<CardState>): number {
  let load = 0;
  for (const state of states) load += 1 / Math.max((state.due - state.lastReview) / day, 1);
  return load;
}

/**
 * The cards a session in [day] studies, from [cards] and their stored [states]; a card is due
 * when it falls due before [day] ends. They are in backlog when more than [backlogDays] of
 * `dailyLoad` are due: the session then takes every due card, earliest due first, ties in the
 * order given, and no new card. Otherwise it takes every due card, then as many cards with no
 * state as [day] has left, oldest first by creation time, ties in the order given.
 */
export function selectQueue<C extends Queueable>(
  cards: readonly C[],
  states: CardStates,
  day: StudyDay,
): SelectedQueue<C> {
  const due: { card: C; due: number }[] = [];
  const fresh: C[] = [];
  const reviewed: CardState[] = [];
  for (const card of cards) {
    const state = states[card.id];
    if (!state) {
      fresh.push(card);
      continue;
    }
    reviewed.push(state);
    if (state.due < day.end) due.push({ card, due: state.due });
  }
  // Array.prototype.sort is stable, so equal times keep the order given.
  if (due.length > backlogDays * dailyLoad(reviewed)) {
    due.sort((a, b) => a.due - b.due);
    return { cards: due.map((entry) => entry.card), backlog: true };
  }
  fresh.sort((a, b) => a.createdAt - b.createdAt);
  return {
    cards: [...due.map((entry) => entry.card), ...fresh.slice(0, day.newCardsLeft)],
    backlog: false,
  };
}

/** How many due and new cards are left in [day] for a session over [cards]. */
export function countToday(
  cards: readonly Queueable[],
  states: CardStates,
  day: StudyDay,
): TodayCount {
  const queue = selectQueue(cards, states, day);
  const review = queue.cards.filter((card) => states[card.id]).length;
  return { review, fresh: queue.cards.length - review, backlog: queue.backlog };
}

/**
 * [queue]'s cards in an order drawn from [random]. In a backlog, each run of
 * [backlogBucketSize] consecutive cards is shuffled in its place, so earlier due cards still
 * come first. Otherwise every order is equally likely: the due cards shuffled, with each new
 * card at a random place among them. Each draw picks the next card from those of its run not
 * yet placed, the first of them on a draw of 0.
 */
export function orderQueue<C>(queue: SelectedQueue<C>, random: Random): C[] {
  const run = queue.backlog ? backlogBucketSize : Math.max(queue.cards.length, 1);
  const ordered: C[] = [];
  for (let start = 0; start < queue.cards.length; start += run) {
    const remaining = queue.cards.slice(start, start + run);
    while (remaining.length > 0) {
      ordered.push(...remaining.splice(random.nextInt(remaining.length), 1));
    }
  }
  return ordered;
}

/**
 * Puts [card] back into [queue], the cards still to show with the next one first, so that a
 * gap drawn from [random] between [reshowGapMin] and [reshowGapMax] other cards come before
 * it, or as many as remain.
 */
export function reinsert<C>(queue: C[], card: C, random: Random): void {
  const gap = reshowGapMin + random.nextInt(reshowGapMax - reshowGapMin + 1);
  queue.splice(Math.min(gap, queue.length), 0, card);
}
