import { cleanup, screen, within } from "@testing-library/react";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";

import { FakePostgrest } from "@/testing/mocks/postgrest";
import { otherUser, testUser } from "@/testing/mocks/handlers";
import { server } from "@/testing/mocks/server";
import { cardRow, day, deckRow, reviewRow, start, stateRow } from "@/testing/library";
import { setRequestCookies } from "@/testing/next-headers";
import { render } from "@/testing/render";
import { signedInCookies } from "@/testing/session";

import { Decks } from "../_components/decks";

vi.mock("next/headers", () => import("@/testing/next-headers"));

const due = { stability: 3, difficulty: 5, lastReview: start - 4 * day, due: start - day };
const notDue = { stability: 30, difficulty: 5, lastReview: start - day, due: start + 9 * day };

describe("the deck list", () => {
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

  /** The row of the deck named [name]: a link named for the deck, its count and its chip. */
  const row = (name: string) => screen.getByRole("link", { name: new RegExp(`^${name}, `) });
  const rowNames = () =>
    within(screen.getByRole("list"))
      .getAllByRole("link")
      .map((link) => link.getAttribute("aria-label"));

  it("shows the server's decks by name, with their card counts and today's chips", async () => {
    postgrest.seed("decks", deckRow("d-es", "Spanish"), deckRow("d-fr", "French"));
    postgrest.seed(
      "cards",
      cardRow("fr-new", "d-fr", "chat"),
      cardRow("fr-due", "d-fr", "chien"),
      cardRow("fr-later", "d-fr", "oiseau"),
      cardRow("es-later", "d-es", "gato"),
    );
    postgrest.seed("card_states", stateRow("fr-due", due), stateRow("fr-later", notDue));
    postgrest.seed("card_states", stateRow("es-later", notDue));

    await render(Decks, {});

    expect(screen.getByRole("heading", { name: "오늘 할 카드 2장" })).toBeInTheDocument();
    expect(screen.getByText("복습 1 · 새 카드 1 · 약 1분")).toBeInTheDocument();
    expect(screen.getByRole("link", { name: "모두 학습" })).toHaveAttribute(
      "href",
      "/study?decks=d-fr,d-es",
    );
    expect(screen.getByRole("heading", { name: "내 덱 2" })).toBeInTheDocument();
    expect(rowNames()).toEqual(["French, 카드 3장, 오늘 2", "Spanish, 카드 1장"]);
    expect(row("French")).toHaveAttribute("href", "/decks/d-fr");
  });

  it("says in the header that new cards wait while more than three days of reviews are due", async () => {
    const paused = "밀린 복습을 마칠 때까지 새 카드는 쉬어요.";
    postgrest.seed("decks", deckRow("d-fr", "French"));
    postgrest.seed("cards", cardRow("fr-new", "d-fr", "chat"), cardRow("fr-due", "d-fr", "chien"));
    postgrest.seed("card_states", stateRow("fr-due", due));
    // Control: one card due every three days is not a backlog.
    await render(Decks, {});
    expect(screen.getByText("복습 1 · 새 카드 1 · 약 1분")).toBeInTheDocument();
    expect(screen.queryByText(paused)).not.toBeInTheDocument();
    cleanup();

    // Two more due after 30 days: three due against a load of about 0.4 a day.
    const overdue = {
      stability: 30,
      difficulty: 5,
      lastReview: start - 31 * day,
      due: start - day,
    };
    postgrest.seed("cards", cardRow("fr-a", "d-fr", "un"), cardRow("fr-b", "d-fr", "deux"));
    postgrest.seed("card_states", stateRow("fr-a", overdue), stateRow("fr-b", overdue));
    await render(Decks, {});

    expect(screen.getByRole("heading", { name: "오늘 할 카드 3장" })).toBeInTheDocument();
    expect(screen.getByText("복습 3 · 새 카드 0 · 약 1분")).toBeInTheDocument();
    expect(screen.getByText(paused)).toBeInTheDocument();
  });

  it("leaves out tombstoned decks and cards, and the cards of a tombstoned deck", async () => {
    postgrest.seed("decks", deckRow("d-fr", "French"), deckRow("d-old", "Old", true));
    postgrest.seed(
      "cards",
      cardRow("fr-live", "d-fr", "chat"),
      cardRow("fr-gone", "d-fr", "chien", day, true),
      cardRow("old-live", "d-old", "maison"),
    );

    await render(Decks, {});

    expect(screen.queryByText("Old")).not.toBeInTheDocument();
    expect(rowNames()).toEqual(["French, 카드 1장, 오늘 1"]);
    expect(screen.getByRole("heading", { name: "오늘 할 카드 1장" })).toBeInTheDocument();
    // Control: the live deck and its live card are read and shown.
    expect(screen.getByRole("heading", { name: "내 덱 1" })).toBeInTheDocument();
  });

  it("leaves out another user's public deck, which row-level security lets it read", async () => {
    const other = otherUser.id;
    postgrest.seed("decks", deckRow("d-fr", "French"), {
      ...deckRow("d-pub", "Public"),
      user_id: other,
      visibility: "public",
    });
    postgrest.seed("cards", cardRow("fr", "d-fr", "chat"), {
      ...cardRow("pub", "d-pub", "maison"),
      user_id: other,
    });

    await render(Decks, {});

    // Control: the user's own deck is read and counted.
    expect(rowNames()).toEqual(["French, 카드 1장, 오늘 1"]);
    expect(screen.getByRole("heading", { name: "오늘 할 카드 1장" })).toBeInTheDocument();
  });

  it("estimates the minutes at the median of the user's latest 200 reviews", async () => {
    postgrest.seed("decks", deckRow("d-fr", "French"));
    postgrest.seed("cards", cardRow("fr-a", "d-fr", "un"), cardRow("fr-b", "d-fr", "deux"));
    // Control: under 20 reviews the pace is 10 s a card, so two cards take about a minute.
    postgrest.seed(
      "reviews",
      ...Array.from({ length: 19 }, (_, index) =>
        reviewRow(`r-few-${String(index)}`, "fr-a", start - day, 90_000),
      ),
    );
    await render(Decks, {});
    expect(screen.getByText("복습 0 · 새 카드 2 · 약 1분")).toBeInTheDocument();
    cleanup();

    // 200 recent reviews at 90 s and 300 older ones at 1 s, stored between them: the median of
    // all 500, or of the first 200 stored, would be 1 s.
    postgrest.seed(
      "reviews",
      ...Array.from({ length: 300 }, (_, index) =>
        reviewRow(`r-old-${String(index)}`, "fr-b", start - 9 * day, 1_000),
      ),
      ...Array.from({ length: 181 }, (_, index) =>
        reviewRow(`r-new-${String(index)}`, "fr-a", start - day, 90_000),
      ),
    );
    await render(Decks, {});
    expect(screen.getByText("복습 0 · 새 카드 2 · 약 3분")).toBeInTheDocument();
  });

  it("marks a deck its owner published with 공개, and no other", async () => {
    postgrest.seed("decks", deckRow("d-fr", "French", false, "public"), deckRow("d-es", "Spanish"));
    postgrest.seed("cards", cardRow("fr", "d-fr", "chat"), cardRow("es", "d-es", "gato"));

    await render(Decks, {});

    expect(rowNames()).toEqual(["French, 카드 1장, 공개, 오늘 1", "Spanish, 카드 1장, 오늘 1"]);
    expect(within(row("French")).getByText("공개")).toBeInTheDocument();
    // Control: the private deck's row carries no chip.
    expect(within(row("Spanish")).queryByText("공개")).not.toBeInTheDocument();
  });

  it("shows each request only its own user's decks, cards, states and pace", async () => {
    postgrest.seed("decks", deckRow("d-fr", "French"), {
      ...deckRow("d-other", "Other"),
      user_id: otherUser.id,
    });
    postgrest.seed("cards", cardRow("fr", "d-fr", "chat"), {
      ...cardRow("other", "d-other", "maison"),
      user_id: otherUser.id,
    });
    postgrest.seed("card_states", {
      ...stateRow("other", {
        stability: 3,
        difficulty: 5,
        lastReview: start - 4 * day,
        due: start - day,
      }),
      user_id: otherUser.id,
    });
    postgrest.seed(
      "reviews",
      ...Array.from({ length: 40 }, (_, index) => ({
        ...reviewRow(`r-other-${String(index)}`, "other", start - day, 600_000),
        user_id: otherUser.id,
      })),
    );

    await render(Decks, {});
    expect(rowNames()).toEqual(["French, 카드 1장, 오늘 1"]);
    expect(screen.getByText("복습 0 · 새 카드 1 · 약 1분")).toBeInTheDocument();
    cleanup();

    // The other user's next request reads theirs, and nothing of the first user's.
    setRequestCookies(await signedInCookies(otherUser));
    await render(Decks, {});
    expect(rowNames()).toEqual(["Other, 카드 1장, 오늘 1"]);
    expect(screen.getByText("복습 1 · 새 카드 0 · 약 10분")).toBeInTheDocument();
  });

  it("carries no account content: neither the email nor 로그아웃", async () => {
    postgrest.seed("decks", deckRow("d-fr", "French"));

    await render(Decks, {});

    // Control: the deck list itself rendered.
    expect(screen.getByRole("heading", { name: "내 덱 1" })).toBeInTheDocument();
    expect(screen.queryByText(testUser.email, { exact: false })).not.toBeInTheDocument();
    expect(screen.queryByRole("button", { name: "로그아웃" })).not.toBeInTheDocument();
  });

  it("reads every page of a library larger than one PostgREST answer", async () => {
    postgrest.seed("decks", deckRow("d-big", "Big"));
    postgrest.seed(
      "cards",
      ...Array.from({ length: 1001 }, (_, index) =>
        cardRow(`c-${String(index)}`, "d-big", `w${String(index)}`),
      ),
    );

    await render(Decks, {});

    // New cards are capped at 20 per session.
    expect(rowNames()).toEqual(["Big, 카드 1001장, 오늘 20"]);
    expect(postgrest.requests.filter((request) => request === "GET cards")).toHaveLength(2);
  });

  it("reads a library of exactly two pages with one request per page, the first counting them", async () => {
    postgrest.seed("decks", deckRow("d-big", "Big"));
    postgrest.seed(
      "cards",
      ...Array.from({ length: 2000 }, (_, index) =>
        cardRow(`c-${String(index)}`, "d-big", `w${String(index)}`),
      ),
    );

    await render(Decks, {});

    // Control: every card is read.
    expect(rowNames()).toEqual(["Big, 카드 2000장, 오늘 20"]);
    expect(postgrest.requests.filter((request) => request === "GET cards")).toHaveLength(2);
  });

  it("reads no card's sides, which the deck list does not show", async () => {
    postgrest.seed("decks", deckRow("d-fr", "French"));
    postgrest.seed("cards", cardRow("fr", "d-fr", "chat"));

    await render(Decks, {});

    // Control: the card is read and counted.
    expect(rowNames()).toEqual(["French, 카드 1장, 오늘 1"]);
    expect(postgrest.selected.filter((read) => read.startsWith("cards: "))).toEqual([
      "cards: id,deck_id,created_at",
    ]);
  });

  it("says the server cannot be reached when PostgREST does not answer", async () => {
    postgrest.fail("decks", 500);

    await render(Decks, {});

    expect(screen.getByRole("alert")).toHaveTextContent(
      "서버에 연결할 수 없어요. 연결을 확인하고 다시 시도해 주세요.",
    );
  });

  it("shows the first-run invitation in place of the today card and the list when there is no deck", async () => {
    const title = "첫 덱을 만들어 볼까요?";
    const pointer =
      "덱은 휴대폰 앱에서 만들어요. 단어장 사진을 찍거나 직접 입력하면 여기에도 보여요.";
    // Control: a user with one deck sees the list and no invitation.
    postgrest.seed("decks", deckRow("d-fr", "French"));
    await render(Decks, {});
    expect(screen.getByRole("heading", { name: "내 덱 1" })).toBeInTheDocument();
    expect(screen.queryByRole("heading", { name: title })).not.toBeInTheDocument();
    cleanup();

    postgrest = new FakePostgrest();
    server.use(...postgrest.handlers);
    await render(Decks, {});

    expect(screen.getByRole("heading", { name: title })).toBeInTheDocument();
    expect(screen.getByText(pointer)).toBeInTheDocument();
    expect(screen.queryByRole("heading", { name: /^내 덱/ })).not.toBeInTheDocument();
    expect(
      screen.queryByRole("heading", { name: "오늘 할 카드를 다 했어요" }),
    ).not.toBeInTheDocument();
    // The web creates nothing and has no public-deck browsing, so the invitation offers no action.
    expect(screen.queryByRole("link")).not.toBeInTheDocument();
    expect(screen.queryByRole("button")).not.toBeInTheDocument();
  });
});
