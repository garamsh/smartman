import { screen } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";

import { otherUser } from "@/testing/mocks/handlers";
import { FakePostgrest } from "@/testing/mocks/postgrest";
import { server } from "@/testing/mocks/server";
import { cardRow, day, deckRow, reviewRow, start, stateRow } from "@/testing/library";
import { setRequestCookies } from "@/testing/next-headers";
import { render } from "@/testing/render";
import { signedInCookies } from "@/testing/session";

import { RecordContent } from "../_components/record";

vi.mock("next/headers", () => import("@/testing/next-headers"));

/** A review of [card] [ago] before [start], "안다" unless [know] is false. */
function answer(id: string, card: string, ago: number, know = true) {
  return { ...reviewRow(id, card, start - ago, 6000), rating: know ? "good" : "again" };
}

/** A stored state reviewed [ago] before [start] with an interval of [interval]. */
const state = (card: string, ago: number, interval: number) =>
  stateRow(card, {
    stability: 5,
    difficulty: 5,
    lastReview: start - ago,
    due: start - ago + interval,
  });

/** The chart or bar whose label starts with [prefix]: its whole label. */
const label = (prefix: string) =>
  screen.getByRole("img", { name: new RegExp(`^${prefix}`) }).getAttribute("aria-label");

describe("the record page", () => {
  let postgrest: FakePostgrest;
  beforeEach(async () => {
    vi.useFakeTimers({ toFake: ["Date"] });
    vi.setSystemTime(start);
    setRequestCookies(await signedInCookies());
    postgrest = new FakePostgrest();
    server.use(...postgrest.handlers);
  });
  afterEach(() => {
    vi.useRealTimers();
  });

  /**
   * A history in Seoul, the zone without a cookie: card a reviewed "안다" 20 and 3 days back; b
   * "모른다" 3 days back with a re-show; a card since deleted "안다" 3 days back; c first answered
   * yesterday; and d "모른다" 40 days back, after its first answer 60 days back.
   */
  function seedHistory() {
    postgrest.seed("decks", deckRow("deck", "French"));
    postgrest.seed(
      "cards",
      cardRow("a", "deck", "chat"),
      cardRow("b", "deck", "chien"),
      cardRow("c", "deck", "oiseau"),
      cardRow("d", "deck", "poisson"),
      cardRow("gone", "deck", "vache", day, true),
    );
    postgrest.seed(
      "reviews",
      answer("a1", "a", 25 * day),
      answer("a2", "a", 20 * day),
      answer("a3", "a", 3 * day),
      answer("b1", "b", 10 * day),
      answer("b2", "b", 3 * day, false),
      answer("b3", "b", 3 * day - 5 * 60_000),
      answer("g1", "gone", 10 * day),
      answer("g2", "gone", 3 * day),
      answer("c1", "c", day),
      answer("d1", "d", 60 * day),
      answer("d2", "d", 40 * day, false),
    );
    postgrest.seed(
      "card_states",
      state("a", 3 * day, 12 * day),
      state("b", 3 * day, day),
      state("c", day, 3 * day),
      state("d", 40 * day, day),
      state("gone", 3 * day, 12 * day),
    );
  }

  it("shows the retention over 30 days by default, then 7 days and every day, with its gap and each day in its label", async () => {
    seedHistory();
    await render(RecordContent, {});

    // 30 days: a's "안다" 20 days back, and a's and the deleted card's "안다" and b's "모른다" 3 days back.
    expect(screen.getByRole("radio", { name: "30일" })).toBeChecked();
    expect(screen.getByText("75%")).toBeInTheDocument();
    expect(screen.getByText("목표보다 15%p 낮아요")).toBeInTheDocument();
    expect(label("복습에서 맞힌 비율")).toBe(
      "복습에서 맞힌 비율, 목표 90%: 12월 26일 100%, 1월 12일 67%",
    );

    await userEvent.click(screen.getByRole("radio", { name: "7일" }));
    expect(screen.getByText("67%")).toBeInTheDocument();
    expect(screen.getByText("목표보다 23%p 낮아요")).toBeInTheDocument();
    expect(label("복습에서 맞힌 비율")).toBe("복습에서 맞힌 비율, 목표 90%: 1월 12일 67%");

    await userEvent.click(screen.getByRole("radio", { name: "전체" }));
    expect(screen.getByText("60%")).toBeInTheDocument();
    expect(screen.getByText("목표보다 30%p 낮아요")).toBeInTheDocument();
  });

  it("labels the retention scale's floor and names the target above the plot, clear of the line (#155)", async () => {
    seedHistory();
    await render(RecordContent, {});

    const chart = screen.getByRole("img", { name: /^복습에서 맞힌 비율/ });
    // The lowest day, 67%, takes the scale down to 60%, and the floor says so.
    expect(chart).toHaveTextContent("100%");
    expect(chart).toHaveTextContent("60%");
    // The target's name sits in its own row above the plot's svg, not inside it.
    const target = screen.getByText("목표 90%");
    expect(target.closest("svg")).toBeNull();
    const plot = chart.querySelector("svg[preserveAspectRatio]");
    expect(plot).not.toBeNull();
    expect(
      target.compareDocumentPosition(plot ?? target) & Node.DOCUMENT_POSITION_FOLLOWING,
    ).toBeTruthy();
  });

  it("shows the recall bands of the cards in the decks, the deleted card's state left out", async () => {
    seedHistory();
    await render(RecordContent, {});

    // a, b, c and d: the deleted card's state is not one of them.
    expect(label("\\d+장 중")).toMatch(/^4장 중 단단함 \d장, 보통 \d장, 곧 잊음 \d장, 평균 \d+%$/);
  });

  it("counts every stored answer in the study days and the streaks, the deleted card's included", async () => {
    seedHistory();
    await render(RecordContent, {});

    expect(screen.getByText("1일 연속 · 최고 1일")).toBeInTheDocument();
    expect(label("최근 12주")).toBe(
      "최근 12주 동안 7일 학습했어요: 11월 16일 1장, 12월 6일 1장, 12월 21일 1장, 12월 26일 1장, 1월 5일 2장, 1월 12일 3장, 1월 14일 1장",
    );
  });

  it("says so in a sentence for each chart with nothing to show", async () => {
    postgrest.seed("decks", deckRow("deck", "French"));
    await render(RecordContent, {});

    expect(screen.getByText("이 기간에 복습한 카드가 없어요.")).toBeInTheDocument();
    expect(screen.getByText("아직 복습한 카드가 없어요.")).toBeInTheDocument();
    expect(screen.getByText("아직 익힌 카드가 없어요.")).toBeInTheDocument();
    expect(label("최근 12주")).toBe("최근 12주 동안 학습한 날이 없어요");
    expect(screen.getByText("0일 연속 · 최고 0일")).toBeInTheDocument();
  });

  it("reads in two requests sent together, and only the signed-in user's rows", async () => {
    seedHistory();
    postgrest.seed("reviews", { ...answer("x1", "a", 2 * day), user_id: otherUser.id });
    await render(RecordContent, {});

    expect(postgrest.requests.toSorted()).toEqual([
      "POST rpc/study_record_cards",
      "POST rpc/study_record_days",
    ]);
    // Another user's answer 2 days back is not a study day of this user's.
    expect(label("최근 12주")).toMatch(/^최근 12주 동안 7일 학습했어요/);
  });

  it("shows why it could not read the record", async () => {
    seedHistory();
    postgrest.fail("reviews", 503);
    await render(RecordContent, {});

    expect(screen.getByRole("alert")).toHaveTextContent(
      "서버에 연결할 수 없어요. 연결을 확인하고 다시 시도해 주세요.",
    );
    expect(screen.queryByText("복습에서 맞힌 비율")).toBeNull();
  });
});
