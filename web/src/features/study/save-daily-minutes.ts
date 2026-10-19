"use server";

import { revalidatePath } from "next/cache";

import { classifyFailure, requestTimeoutMs, type ServerFailure } from "@/supabase/failure";
import { createClient } from "@/supabase/server";
import { readUserId } from "@/supabase/session";

import { maxDailyMinutes, minDailyMinutes } from "./queue";

/** What saving the daily minutes returns: saved, or the sentence that says why not. */
export type SaveMinutesResult = { saved: true } | { saved: false; message: string };

const failureMessages: Record<ServerFailure | "malformed", string> = {
  unreachable: "공부 시간을 저장하지 못했어요. 연결을 확인하고 다시 시도해 주세요.",
  rejected: "로그인이 끝나 공부 시간을 저장하지 못했어요. 다시 로그인해 주세요.",
  failed: "공부 시간을 저장하지 못했어요. 잠시 후 다시 시도해 주세요.",
  malformed: "공부 시간은 5분에서 180분 사이로 골라 주세요.",
};

/**
 * Saves [minutes] as the signed-in user's daily study minutes through `save_study_settings`, set
 * now, so the later edit wins against the phone's (ADR 0085), and revalidates the pages that
 * count today's cards. Minutes outside 5 to 180, or not a whole number, are refused unsent.
 */
export async function saveDailyMinutes(minutes: number): Promise<SaveMinutesResult> {
  // The argument crossed the network, whatever its declared type.
  if (
    typeof minutes !== "number" ||
    !Number.isInteger(minutes) ||
    minutes < minDailyMinutes ||
    minutes > maxDailyMinutes
  ) {
    return { saved: false, message: failureMessages.malformed };
  }
  const supabase = await createClient();
  const session = await readUserId(supabase);
  if ("failure" in session) return { saved: false, message: failureMessages[session.failure] };
  const write = await supabase
    .rpc("save_study_settings", {
      daily_minutes: minutes,
      updated_at: new Date().toISOString(),
    })
    .abortSignal(AbortSignal.timeout(requestTimeoutMs));
  if (write.error) {
    return { saved: false, message: failureMessages[classifyFailure(write.error, write.status)] };
  }
  revalidatePath("/", "layout");
  return { saved: true };
}
