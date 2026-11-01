import { cleanup, screen, within } from "@testing-library/react";
import { beforeEach, describe, expect, it, vi } from "vitest";

import { http, HttpResponse } from "msw";

import { FakeAdmin } from "@/testing/mocks/admin";
import { otherUser, supabaseUrl, testUser } from "@/testing/mocks/handlers";
import { server } from "@/testing/mocks/server";
import { setRequestCookies } from "@/testing/next-headers";
import { render } from "@/testing/render";
import { signedInCookies } from "@/testing/session";

import { ExtractionsContent } from "../_components/content";

vi.mock("next/headers", () => import("@/testing/next-headers"));

/** Signs the next request in as [user], with the browser's zone UTC. */
async function signIn(user: typeof testUser | typeof otherUser = testUser) {
  setRequestCookies([...(await signedInCookies(user)), { name: "smartman-tz", value: "UTC" }]);
}

/** The UTC day [offset] days from now, as YYYY-MM-DD. */
const utcDay = (offset = 0) =>
  new Date(Date.now() + offset * 86_400_000).toISOString().slice(0, 10);

/** A recorded call as `admin_extraction_calls` answers it. */
function call(id: number, fields: Record<string, unknown> = {}) {
  return {
    usage_id: id,
    created_at: "2026-11-01T03:04:00Z",
    user_id: otherUser.id,
    plan: "free",
    model: "anthropic/claude-haiku-5.5",
    prompt_version_id: 10,
    outcome: "ok",
    attempts: 1,
    latency_ms: 12_345,
    cards_returned: 14,
    cards_dropped: 0,
    failures: [],
    ...fields,
  };
}

/** One day's counts for one version as `admin_extraction_failures` answers them. */
function counts(day: string, version: number, fields: Record<string, number>) {
  return {
    day,
    prompt_version_id: version,
    calls: 0,
    ok: 0,
    no_cards: 0,
    invalid_output: 0,
    model_error: 0,
    retried: 0,
    recovered: 0,
    failure_rate: null,
    unrecorded: 0,
    ...fields,
  };
}

const unrecorded = {
  outcome: null,
  attempts: null,
  latency_ms: null,
  cards_returned: null,
  cards_dropped: null,
  failures: null,
};

const page = (before?: string) =>
  render(ExtractionsContent, {
    searchParams: Promise.resolve(before === undefined ? {} : { before }),
  });

let admin: FakeAdmin;
beforeEach(async () => {
  admin = new FakeAdmin();
  server.use(...admin.handlers);
  await signIn();
});

describe("the extraction outcomes page", () => {
  it("shows the failure rate of the last 30 days with each outcome's count, by day and by version", async () => {
    admin.extractionFailures = [
      counts(utcDay(-1), 9, { calls: 10, ok: 6, invalid_output: 3, model_error: 1, retried: 4 }),
      counts(utcDay(), 9, { calls: 10, ok: 10, unrecorded: 1 }),
      counts(utcDay(), 10, {
        calls: 30,
        ok: 27,
        no_cards: 2,
        model_error: 1,
        retried: 3,
        recovered: 2,
      }),
    ];
    await page();

    const period = within(screen.getByRole("region", { name: "최근 30일" }));
    // 5 of 50 recorded calls failed.
    expect(period.getByText("실패율").nextSibling).toHaveTextContent("10.0%");
    expect(period.getByText("성공").nextSibling).toHaveTextContent("43건");
    expect(period.getByText("카드 없음").nextSibling).toHaveTextContent("2건");
    expect(period.getByText("형식 오류").nextSibling).toHaveTextContent("3건");
    expect(period.getByText("모델 오류").nextSibling).toHaveTextContent("2건");
    expect(period.getByText("재시도").nextSibling).toHaveTextContent("7건 중 2건 복구");
    expect(period.getByText("기록 없음").nextSibling).toHaveTextContent("1건");

    const daily = within(screen.getByRole("region", { name: "날짜별 실패율" }));
    expect(daily.getByRole("img")).toHaveAccessibleName(
      `날짜별 실패율, 최근 30일: ${utcDay(-1).slice(5)} 40.0%, ${utcDay().slice(5)} 2.5%`,
    );

    const versions = within(screen.getByRole("region", { name: "프롬프트 버전별" }));
    const rows = versions.getAllByRole("listitem");
    expect(rows.map((row) => within(row).getByRole("link").textContent)).toEqual([
      "버전 10",
      "버전 9",
    ]);
    expect(within(rows[0] as HTMLElement).getByRole("link")).toHaveAttribute(
      "href",
      "/admin/prompts/10",
    );
    // A row carries its rate and its counts together, so a substring is right.
    expect(rows[0]).toHaveTextContent(/실패 3\.3%/);
    expect(rows[1]).toHaveTextContent(
      /실패 20\.0%추출 20건 · 형식 오류 3건 · 모델 오류 1건 · 재시도 4건 중 0건 복구/,
    );
    expect(admin.calls).toContain('admin_extraction_failures {"days":30}');
  });

  it("lists the recent extractions with their time, plan, version, outcome, calls, latency and cards, and no user", async () => {
    admin.extractionCalls = [
      call(42, { cards_dropped: 2 }),
      call(41, {
        plan: "pro",
        prompt_version_id: 9,
        outcome: "model_error",
        attempts: 2,
        latency_ms: 95_000,
        cards_returned: 0,
        failures: ["timeout", "model_error"],
      }),
      call(40, { outcome: "ok", attempts: 2, failures: ["invalid_output"] }),
      call(39, { ...unrecorded, user_id: testUser.id }),
    ];
    const { container } = await page();

    const list = within(screen.getByRole("list", { name: "최근 추출" }));
    expect(list.getAllByRole("listitem").map((row) => row.textContent)).toEqual([
      "성공2026-11-01 03:04무료 · 버전 10 · 시도 1회 · 12.3초 · 카드 14장 · 거른 카드 2장",
      "모델 오류2026-11-01 03:04프로 · 버전 9 · 시도 2회 (시간 초과, 모델 오류) · 95.0초 · 카드 0장",
      "성공2026-11-01 03:04무료 · 버전 10 · 시도 2회 (형식 오류) · 12.3초 · 카드 14장",
      "기록 없음2026-11-01 03:04무료 · 버전 10",
    ]);
    // Nothing names the user each call served.
    for (const user of [testUser, otherUser]) {
      expect(container.innerHTML).not.toContain(user.id);
      expect(container.innerHTML).not.toContain(user.email);
    }
    expect(admin.calls).toContain('admin_extraction_calls {"before":null,"page_size":50}');
    // A page shorter than a full one is the last.
    expect(screen.queryByRole("link", { name: "이전 추출 더 보기" })).not.toBeInTheDocument();
  });

  it("links a full page to the one before it, and that page back to the newest", async () => {
    admin.extractionCalls = Array.from({ length: 60 }, (_, index) => call(1000 - index));
    await page();
    expect(screen.getAllByRole("listitem")).toHaveLength(50);
    expect(screen.getByRole("link", { name: "이전 추출 더 보기" })).toHaveAttribute(
      "href",
      "/admin/extractions?before=951",
    );
    expect(screen.queryByRole("link", { name: "최신 추출로" })).not.toBeInTheDocument();

    cleanup();
    await page("951");
    expect(admin.calls).toContain('admin_extraction_calls {"before":951,"page_size":50}');
    const list = within(screen.getByRole("list", { name: "최근 추출" }));
    expect(list.getAllByRole("listitem")).toHaveLength(10);
    expect(screen.getByRole("link", { name: "최신 추출로" })).toHaveAttribute(
      "href",
      "/admin/extractions",
    );
    expect(screen.queryByRole("link", { name: "이전 추출 더 보기" })).not.toBeInTheDocument();
  });

  it("says when nothing was recorded, in the period and in the list", async () => {
    await page();
    expect(
      screen.getAllByText("기록된 추출이 없어요. 사진으로 카드를 만들면 여기에 쌓여요.", {
        exact: false,
      }),
    ).toHaveLength(2);
    expect(screen.queryByRole("region", { name: "날짜별 실패율" })).not.toBeInTheDocument();
    expect(screen.queryByRole("list", { name: "최근 추출" })).not.toBeInTheDocument();

    cleanup();
    await page("12");
    expect(
      screen.getByText("이보다 이전 추출이 없어요. 최신 추출로 돌아가 보세요."),
    ).toBeInTheDocument();
  });

  it("says a user who is not an admin may not see it, against an admin's rows", async () => {
    admin.extractionCalls = [call(42)];
    await signIn(otherUser);
    await page();
    expect(screen.getByRole("alert")).toHaveTextContent("관리자만 볼 수 있어요.");
    expect(screen.queryByRole("list", { name: "최근 추출" })).not.toBeInTheDocument();

    // Control: the admin sees the row.
    cleanup();
    await signIn();
    await page();
    expect(screen.getByRole("list", { name: "최근 추출" })).toBeInTheDocument();
  });

  it("says it could not read an answer whose outcome's parts disagree, against one whose agree", async () => {
    admin.extractionCalls = [call(42, { ...unrecorded, attempts: 1 })];
    await page();
    expect(screen.getByRole("alert")).toHaveTextContent(
      "받은 답을 읽지 못했어요. 페이지를 새로 고친 뒤 다시 시도해 주세요.",
    );
    expect(screen.getByRole("button", { name: "다시 시도" })).toBeInTheDocument();

    // Control: the same row with every part of its outcome null is read.
    cleanup();
    admin.extractionCalls = [call(42, unrecorded)];
    await page();
    expect(screen.queryByRole("alert")).not.toBeInTheDocument();
    expect(screen.getByRole("list", { name: "최근 추출" })).toHaveTextContent("기록 없음");
  });

  it("says it could not load when the server fails, with a way to try again", async () => {
    server.use(
      http.post(`${supabaseUrl}/rest/v1/rpc/admin_extraction_failures`, () =>
        HttpResponse.json({ code: "P0001", message: "boom" }, { status: 400 }),
      ),
    );
    await page();
    expect(screen.getByRole("alert")).toHaveTextContent(
      "불러오지 못했어요. 잠시 후 다시 시도해 주세요.",
    );
    expect(screen.getByRole("button", { name: "다시 시도" })).toBeInTheDocument();
  });
});
