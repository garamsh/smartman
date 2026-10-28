"use server";

import { env } from "@/env";
import { createClient } from "@/supabase/server";
import { readUserId } from "@/supabase/session";
import { field } from "@/supabase/row";
import { parseCandidates, type Candidate } from "./photo-candidates";

/** A per-photo result, without exposing service errors or credentials. */
export type Extraction = { cards: Candidate[] } | { message: string };
/** Calls the existing extraction function as the verified user, without a browser CORS request. */
export async function readPhoto(form: FormData): Promise<Extraction> {
  if (!(form instanceof FormData)) return { message: "사진을 다시 골라 주세요" };
  const file = form.get("photo");
  if (!(file instanceof File) || file.size === 0 || file.size > 3 * 1024 * 1024)
    return { message: "사진을 줄여 다시 골라 주세요" };
  const client = await createClient();
  if ("failure" in (await readUserId(client))) return { message: "다시 로그인해 주세요" };
  const session = await client.auth.getSession();
  const token = session.data.session?.access_token;
  if (!token) return { message: "다시 로그인해 주세요" };
  try {
    const bytes = new Uint8Array(await file.arrayBuffer());
    const jpeg = bytes[0] === 255 && bytes[1] === 216 && bytes[2] === 255;
    const png = bytes[0] === 137 && bytes[1] === 80 && bytes[2] === 78 && bytes[3] === 71;
    const webp =
      String.fromCharCode(...bytes.slice(0, 4)) === "RIFF" &&
      String.fromCharCode(...bytes.slice(8, 12)) === "WEBP";
    if (!jpeg && !png && !webp) return { message: "JPEG, PNG, WebP 사진을 골라 주세요" };
    const response = await fetch(
      `${env.supabaseUrl.replace(/\/$/u, "")}/functions/v1/extract-cards`,
      {
        method: "POST",
        headers: {
          Authorization: `Bearer ${token}`,
          apikey: env.supabasePublishableKey,
          "Content-Type": "application/json",
        },
        body: JSON.stringify({ image: Buffer.from(bytes).toString("base64") }),
        signal: AbortSignal.timeout(90_000),
      },
    );
    const body: unknown = await response.json().catch(() => null);
    if (response.ok) {
      const cards = parseCandidates(body);
      return cards
        ? { cards }
        : { message: "사진의 카드 내용을 읽지 못했어요. 다시 시도해 주세요." };
    }
    if (response.status === 429) {
      const limit = field(body, "photo_limit");
      const period = field(body, "period");
      if (typeof limit === "number" && (period === "day" || period === "month"))
        return {
          message: `${period === "day" ? "오늘" : "이번 달"} 사진 ${String(limit)}장을 모두 읽었어요. 다음 기간에 다시 시도해 주세요.`,
        };
    }
    const messages: Record<number, string> = {
      401: "다시 로그인해 주세요",
      403: "사진을 읽을 수 없는 계정이에요. 설정에서 계정을 확인해 주세요.",
      413: "사진은 6MB 이하로 골라 주세요",
      415: "JPEG, PNG, WebP 사진을 골라 주세요",
      422: "카드를 찾지 못했어요. 글자가 선명한 사진을 골라 주세요.",
    };
    return { message: messages[response.status] ?? "사진을 읽지 못했어요. 다시 시도해 주세요." };
  } catch {
    return { message: "사진을 읽지 못했어요. 연결을 확인하고 다시 시도해 주세요." };
  }
}
