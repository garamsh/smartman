import { ReadFailure, readDeckList } from "@/features/decks";
import {
  countDay,
  DailyMinutes,
  dayPlanOf,
  type MinutesPlan,
  newCards,
  readToday,
  readyServerEngine,
} from "@/features/study";

type Failure = Parameters<typeof ReadFailure>[0]["failure"];

/**
 * The daily study minutes and what they mean for today's new cards, read on the server over every
 * deck, as the 오늘 page reads its day: today's list places the cards.
 */
export async function readStudySetting(): Promise<
  { minutes: number; plan: MinutesPlan } | { failure: Failure }
> {
  const [read, today] = await Promise.all([readDeckList(), readToday()]);
  if ("failure" in read) return read;
  if ("failure" in today) return today;
  const engine = await readyServerEngine();
  if ("failure" in engine) return engine;
  const { cards } = read.library;
  const { day, states, answers, pace, dailyMinutes, dueAtStart, startedToday } = today.today;
  return {
    minutes: dailyMinutes,
    plan: {
      due: dueAtStart,
      started: startedToday,
      unstarted: newCards(cards, states).length,
      backlog: countDay(dayPlanOf(cards, states, day, answers), states).backlog,
      pace,
    },
  };
}

/** "공부": the daily study minutes' row, the one place they are changed, or why they cannot be read. */
export function StudySetting({
  setting,
}: {
  setting: Awaited<ReturnType<typeof readStudySetting>>;
}) {
  return (
    <section aria-labelledby="study-section" className="flex flex-col gap-3">
      <h2 id="study-section" className="text-section text-ink-2">
        공부
      </h2>
      {"failure" in setting ? (
        <ReadFailure failure={setting.failure} />
      ) : (
        <DailyMinutes minutes={setting.minutes} plan={setting.plan} />
      )}
    </section>
  );
}
