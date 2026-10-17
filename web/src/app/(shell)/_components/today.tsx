import { Flame, Play } from "lucide-react";
import Link from "next/link";

import { type Deck, DeckTile, EmptyHome, ReadFailure, readDeckList } from "@/features/decks";
import {
  countToday,
  dailyGoal,
  deckProgress,
  forecast,
  readRecentRetention,
  readToday,
  RetentionPreview,
  selectQueue,
  sessionMinutes,
  statusLine,
  studyDayEnd,
  todayStatus,
} from "@/features/study";

import { EnterLink } from "./enter-link";
import { studyHref } from "./study-href";

/** Noon of the study day starting at [start], which names its calendar date in any zone. */
const noon = (start: number) => start + 12 * 3_600_000;

/**
 * The 오늘 page's content, read on the server: the today card over every deck, the next seven
 * days, today's decks and the retention of the last 30 days; with no deck, the first-run
 * invitation.
 */
export async function Today() {
  const [read, today, retention] = await Promise.all([
    readDeckList(),
    readToday({ streak: true }),
    readRecentRetention(),
  ]);
  if ("failure" in read) return <ReadFailure failure={read.failure} />;
  if ("failure" in today) return <ReadFailure failure={today.failure} />;
  if ("failure" in retention) return <ReadFailure failure={retention.failure} />;
  const { decks, cards } = read.library;
  const { day, states, pace, answers, streakBefore, timeZone } = today.today;
  const header = (
    <header className="flex flex-wrap items-baseline gap-x-3">
      <h1 className="text-display">오늘</h1>
      <span className="text-label font-normal text-muted">
        {new Intl.DateTimeFormat("ko-KR", {
          month: "long",
          day: "numeric",
          weekday: "long",
          timeZone,
        }).format(noon(day.start))}
      </span>
    </header>
  );
  if (decks.length === 0) {
    return (
      <>
        {header}
        <EmptyHome />
      </>
    );
  }

  const count = countToday(cards, states, day);
  const total = count.review + count.fresh;
  const ids = new Set(cards.map((card) => card.id));
  const goal = dailyGoal(
    answers.filter((answer) => ids.has(answer.cardId)),
    selectQueue(cards, states, day).cards.map((card) => card.id),
    day,
  );
  const streak = streakBefore + (answers.length > 0 ? 1 : 0);
  const stored = Object.values(states).flatMap((state) => (state ? [state] : []));
  const days = forecast(stored, day, total, timeZone);
  const starts = [day.start];
  while (starts.length < days.length) {
    starts.push(studyDayEnd(starts[starts.length - 1] ?? day.start, timeZone));
  }
  const rows = decks.flatMap((deck) => {
    const own = cards.filter((card) => card.deckId === deck.id);
    const left = countToday(own, states, day);
    const n = left.review + left.fresh;
    if (n === 0) return [];
    const { mastered } = deckProgress(own, states);
    return [{ deck, today: n, mastered: mastered / own.length }];
  });

  return (
    <>
      {header}
      <div className="grid gap-4 lg:grid-cols-2">
        <section
          aria-labelledby="today-title"
          className="flex flex-wrap items-center gap-6 rounded-card bg-hero p-6 text-on-hero shadow-card lg:col-span-2 lg:p-7"
        >
          <div className="flex min-w-0 flex-[1_1_220px] flex-col gap-2">
            {total === 0 ? (
              <h2 id="today-title" className="text-title">
                오늘 할 카드를 다 했어요
              </h2>
            ) : (
              <>
                <p className="text-label font-normal">오늘 할 카드</p>
                <h2 id="today-title" aria-label={`오늘 할 카드 ${String(total)}장`}>
                  <span className="text-figure">{total}</span>{" "}
                  <span className="text-headline">
                    장 · 약 {sessionMinutes(count.review, count.fresh, pace)}분
                  </span>
                </h2>
              </>
            )}
            <p className="flex flex-wrap items-center gap-2 text-secondary">
              {streak > 0 && (
                <span className="flex items-center gap-1 rounded-full border border-on-hero/40 px-2.5 py-1 font-bold">
                  <Flame aria-hidden className="size-4" strokeWidth={2} />
                  {streak}일 연속
                </span>
              )}
              <span className="break-keep">
                {total === 0
                  ? goal.goal > 0 && `목표 ${String(goal.goal)}장 달성`
                  : count.backlog
                    ? "밀린 복습을 마칠 때까지 새 카드는 쉬어요."
                    : statusLine(todayStatus(goal, streak))}
              </span>
            </p>
          </div>
          <GoalRing done={goal.done} goal={goal.goal} />
          <EnterLink
            href={studyHref(decks.map((deck) => deck.id))}
            label={total === 0 ? "계속 학습" : "모두 학습"}
          />
        </section>
        <Forecast days={days} starts={starts} timeZone={timeZone} done={total === 0} />
        {rows.length > 0 && <TodayDecks rows={rows} />}
        <RetentionPreview days={retention.days} timeZone={retention.timeZone} />
      </div>
    </>
  );
}

/** The daily goal as a ring, done over goal in its middle, read as one sentence. */
function GoalRing({ done, goal }: { done: number; goal: number }) {
  const radius = 42;
  const length = 2 * Math.PI * radius;
  const fraction = goal === 0 ? 0 : done / goal;
  return (
    <div
      role="img"
      aria-label={`하루 목표 ${String(goal)}장 중 ${String(done)}장`}
      className="relative flex size-24 shrink-0 items-center justify-center"
    >
      <svg aria-hidden viewBox="0 0 96 96" className="absolute inset-0 size-full -rotate-90">
        <circle
          cx="48"
          cy="48"
          r={radius}
          fill="none"
          strokeWidth="8"
          className="stroke-on-hero/20"
        />
        {/* At zero a round cap would still draw a dot. */}
        {fraction > 0 && (
          <circle
            cx="48"
            cy="48"
            r={radius}
            fill="none"
            strokeWidth="8"
            strokeLinecap="round"
            strokeDasharray={`${String(length * fraction)} ${String(length)}`}
            className="stroke-on-hero"
          />
        )}
      </svg>
      <span className="flex flex-col items-center">
        <span className="text-headline">{done}</span>
        <span className="text-micro">/ {goal}</span>
      </span>
    </div>
  );
}

/** The next seven days as bars, today's in ink, read as one line of each day and its count. */
function Forecast({
  days,
  starts,
  timeZone,
  done,
}: {
  days: number[];
  starts: number[];
  timeZone: string;
  done: boolean;
}) {
  const weekday = new Intl.DateTimeFormat("ko-KR", { weekday: "short", timeZone });
  const labels = starts.map((start, index) =>
    index === 0 ? "오늘" : index === 1 ? "내일" : weekday.format(noon(start)),
  );
  const week = days.reduce((sum, value) => sum + value, 0);
  const highest = Math.max(1, ...days);
  return (
    <section
      aria-labelledby="forecast-title"
      className="flex flex-col gap-3.5 rounded-card bg-surface p-5"
    >
      <div className="flex items-baseline justify-between gap-3">
        <h2 id="forecast-title" className="text-body-strong">
          앞으로 7일
        </h2>
        <span className="text-caption text-muted">
          {done
            ? `이번 주 ${String(week)}장`
            : `내일 ${String(days[1] ?? 0)}장 · 이번 주 ${String(week)}장`}
        </span>
      </div>
      <div
        role="img"
        aria-label={labels
          .map((label, index) => `${label} ${String(days[index] ?? 0)}장`)
          .join(", ")}
        className="grid h-28 grid-cols-7 gap-2.5"
      >
        {days.map((value, index) => (
          <div key={labels[index]} className="flex flex-col items-center justify-end gap-1">
            <span className="text-micro font-bold">{value}</span>
            <span
              className={`w-full rounded-md ${index === 0 ? "bg-ink" : "bg-outline"}`}
              style={{ height: `${String(Math.max(4, (value / highest) * 64))}px` }}
            />
            <span className="text-micro text-muted">{labels[index]}</span>
          </div>
        ))}
      </div>
    </section>
  );
}

/** Each deck with cards left today, which opens a session over it. */
function TodayDecks({ rows }: { rows: { deck: Deck; today: number; mastered: number }[] }) {
  return (
    <section
      aria-labelledby="today-decks-title"
      className="flex flex-col gap-1.5 rounded-card bg-surface p-5"
    >
      <h2 id="today-decks-title" className="text-body-strong">
        오늘 할 덱
      </h2>
      <ul className="flex flex-col">
        {rows.map(({ deck, today, mastered }) => (
          <li key={deck.id}>
            <Link
              href={studyHref([deck.id])}
              aria-label={`${deck.name}, 오늘 ${String(today)}장 학습`}
              className="flex min-h-13 items-center gap-3 rounded-field px-2.5 focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-ink"
            >
              <DeckTile deck={deck} size="size-8.5 text-secondary" />
              <span className="flex min-w-0 flex-1 flex-col gap-1">
                <span className="truncate text-label">{deck.name}</span>
                <span aria-hidden className="h-1.5 overflow-hidden rounded-full bg-hairline">
                  <span
                    className="block h-full bg-ink"
                    style={{ width: `${String(mastered * 100)}%` }}
                  />
                </span>
              </span>
              <span className="text-caption font-bold">{today}장</span>
              <Play aria-hidden className="size-small-icon" strokeWidth={2} />
            </Link>
          </li>
        ))}
      </ul>
    </section>
  );
}
