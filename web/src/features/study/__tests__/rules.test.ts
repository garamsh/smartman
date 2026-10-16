// @vitest-environment node
import { readFileSync } from "node:fs";
import path from "node:path";

import { describe, expect, it } from "vitest";

import * as queue from "../queue";

const root = path.join(import.meta.dirname, "../../../../..");
const queueDart = readFileSync(path.join(root, "app/lib/study/src/queue.dart"), "utf8");

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
  newCardLimit: queue.newCardLimit,
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
      queueDart.replace("const newCardLimit = 20;", "const newCardLimit = 21;"),
    );
    expect(changed.get("newCardLimit")).not.toBe(shared.newCardLimit);
  });

  it("are every rule queue.dart declares, so a new one is compared too", () => {
    expect([...dartConstants(queueDart).keys()].sort()).toEqual(Object.keys(shared).sort());
  });
});
