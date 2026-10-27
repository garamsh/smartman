import { beforeEach, describe, expect, it, vi } from "vitest";

import { otherUser, testUser } from "@/testing/mocks/handlers";
import { FakePostgrest } from "@/testing/mocks/postgrest";
import { server } from "@/testing/mocks/server";
import { setRequestCookies } from "@/testing/next-headers";
import { signedInCookies } from "@/testing/session";

import { saveDailyMinutes } from "../save-daily-minutes";

vi.mock("next/headers", () => import("@/testing/next-headers"));
const revalidated = vi.hoisted(() => [] as string[]);
vi.mock("next/cache", () => ({
  revalidatePath: (path: string) => {
    revalidated.push(path);
  },
}));

let postgrest: FakePostgrest;
beforeEach(async () => {
  revalidated.length = 0;
  postgrest = new FakePostgrest();
  server.use(...postgrest.handlers);
  setRequestCookies(await signedInCookies(testUser));
});

describe("saving the daily study minutes", () => {
  it("stores the signed-in user's minutes, alone, and revalidates the pages that count today", async () => {
    expect(await saveDailyMinutes(45)).toEqual({ saved: true });

    expect(postgrest.studySettings.get(testUser.id)?.daily_minutes).toBe(45);
    expect(postgrest.studySettings.has(otherUser.id)).toBe(false);
    expect(revalidated).toEqual(["/"]);
  });

  it("keeps the later edit: a save now replaces an earlier one, not a later one from the phone", async () => {
    postgrest.studySettings.set(testUser.id, {
      daily_minutes: 15,
      updated_at: new Date(Date.now() + 3_600_000).toISOString(),
    });
    await saveDailyMinutes(45);
    expect(postgrest.studySettings.get(testUser.id)?.daily_minutes).toBe(15);
    // Control: against an earlier one, the save wins.
    postgrest.studySettings.set(testUser.id, {
      daily_minutes: 15,
      updated_at: new Date(0).toISOString(),
    });
    await saveDailyMinutes(45);
    expect(postgrest.studySettings.get(testUser.id)?.daily_minutes).toBe(45);
  });

  it("refuses minutes outside 5 to 180, or not whole, without asking the server", async () => {
    for (const minutes of [4, 181, 12.5, Number.NaN]) {
      expect(await saveDailyMinutes(minutes)).toEqual({
        saved: false,
        message: "학습 시간은 5분에서 180분 사이로 골라 주세요.",
      });
    }
    expect(postgrest.requests).toEqual([]);
    // Control: the bounds themselves are saved.
    expect(await saveDailyMinutes(5)).toEqual({ saved: true });
    expect(await saveDailyMinutes(180)).toEqual({ saved: true });
  });

  it("says when no session is signed in, saving nothing", async () => {
    setRequestCookies([]);
    expect(await saveDailyMinutes(30)).toMatchObject({ saved: false });
    expect(postgrest.studySettings.size).toBe(0);
  });
});
