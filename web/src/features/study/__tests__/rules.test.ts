// @vitest-environment node
import { readdirSync, readFileSync } from "node:fs";
import path from "node:path";

import { describe, expect, it } from "vitest";

import * as queue from "../queue";

const root = path.join(import.meta.dirname, "../../../../..");
const queueDart = readFileSync(path.join(root, "app/lib/study/src/queue.dart"), "utf8");
const migrationsDir = path.join(root, "supabase/migrations");
const migrations = readdirSync(migrationsDir)
  .filter((name) => name.endsWith(".sql"))
  .map((name) => ({ name, text: readFileSync(path.join(migrationsDir, name), "utf8") }));

/** Every whole-number top-level `const` queue.dart declares, by name. */
function dartConstants(source: string): Map<string, number> {
  return new Map(
    [...source.matchAll(/^const (\w+) = (\d+);$/gm)].map(([, name, value]) => [
      String(name),
      Number(value),
    ]),
  );
}

/** The rules both clients apply, each a constant of the same name in queue.dart and queue.ts. */
const shared = {
  defaultDailyMinutes: queue.defaultDailyMinutes,
  minDailyMinutes: queue.minDailyMinutes,
  maxDailyMinutes: queue.maxDailyMinutes,
  studyDayWindow: queue.studyDayWindow,
  paceHalfLife: queue.paceHalfLife,
  answerCapMs: queue.answerCapMs,
  paceMinimum: queue.paceMinimum,
  defaultAnswerMs: queue.defaultAnswerMs,
  studyDayStartHour: queue.studyDayStartHour,
  reshowGapMin: queue.reshowGapMin,
  reshowGapMax: queue.reshowGapMax,
  backlogDays: queue.backlogDays,
  backlogBucketSize: queue.backlogBucketSize,
};

describe("the queue rules", () => {
  it("are the phone's: each constant of queue.ts equals queue.dart's of the same name", () => {
    const dart = dartConstants(queueDart);

    for (const [name, value] of Object.entries(shared)) {
      expect({ name, value: dart.get(name) }).toEqual({ name, value });
    }
    // Control: the comparison sees a changed value.
    const changed = dartConstants(
      queueDart.replace("const defaultDailyMinutes = 20;", "const defaultDailyMinutes = 21;"),
    );
    expect(changed.get("defaultDailyMinutes")).not.toBe(shared.defaultDailyMinutes);
  });

  it("are every rule queue.dart declares, so a new one is compared too", () => {
    expect([...dartConstants(queueDart).keys()].sort()).toEqual(Object.keys(shared).sort());
  });

  it("offer the phone's daily minute choices, and the server's bounds on the minutes", () => {
    const presets = /^const dailyMinutePresets = \[([\d, ]+)\];$/m.exec(queueDart)?.[1];
    expect(presets?.split(", ").map(Number)).toEqual([...queue.dailyMinutePresets]);
    const check =
      /daily_minutes integer not null check \(daily_minutes between (\d+) and (\d+)\)/.exec(
        migrations.map((file) => file.text).join("\n"),
      );
    expect([Number(check?.[1]), Number(check?.[2])]).toEqual([
      queue.minDailyMinutes,
      queue.maxDailyMinutes,
    ]);
  });

  it("start the server's study days at studyDayStartHour, as the latest migration defines it", () => {
    expect(serverStartHour(migrations)).toBe(queue.studyDayStartHour);
    // Control: a later migration that moves the hour is the one read.
    const moved = [...migrations, { name: "99999999999999_moved.sql", text: hourFunction(5) }];
    expect(serverStartHour(moved)).toBe(5);
  });
});

/** A migration's definition of `public.study_day_start_hour()` returning [hour]. */
function hourFunction(hour: number): string {
  return `create or replace function public.study_day_start_hour() returns integer\nlanguage sql\nas $$\n  select ${String(hour)}\n$$;`;
}

/**
 * The hour `public.study_day_start_hour()` returns in the last migration, in the order they are
 * applied, that defines it; the server's study-day functions read their day's start from it.
 */
function serverStartHour(files: readonly { name: string; text: string }[]): number | undefined {
  const definition =
    /create (?:or replace )?function public\.study_day_start_hour\(\)[^$]*\$\$\s*select (\d+)\s*\$\$/g;
  let hour: number | undefined;
  for (const file of [...files].sort((a, b) => (a.name < b.name ? -1 : 1))) {
    for (const [, value] of file.text.matchAll(definition)) hour = Number(value);
  }
  return hour;
}
