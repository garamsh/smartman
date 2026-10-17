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
import { Study } from "../study/_components/study";

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
  /** The header's line of counts and minutes. */
  const counts = () =>
    screen.getByText(
      (_, element) => /^복습 \d+ · 새 카드 \d+ · 약 \d+분$/.test(element?.textContent ?? ""),
      { ignore: "html, body, main, div, section, header" },
    ).textContent;
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

  it("counts the new cards left today across every deck, in the time zone the browser's cookie names", async () => {
    postgrest.seed("decks", deckRow("d-a", "Alpha"), deckRow("d-b", "Beta"));
    postgrest.seed(
      "cards",
      ...Array.from({ length: 25 }, (_, index) =>
        cardRow(`a${String(index)}`, "d-a", `alpha ${String(index)}`),
      ),
      cardRow("b-answered", "d-b", "beta"),
    );
    // Beta's card was first answered at 15:00 UTC the day before: 00:00 in Seoul, the day
    // before that study day; 07:00 in Los Angeles, inside the study day there.
    const answeredAt = start - 18 * 3_600_000;
    postgrest.seed("card_states", stateRow("b-answered", { ...notDue, lastReview: answeredAt }));
    postgrest.seed("reviews", reviewRow("r1", "b-answered", answeredAt, 1_000));

    // Without the cookie the day is read in Seoul.
    await render(Decks, {});
    expect(screen.getByRole("heading", { name: "오늘 할 카드 20장" })).toBeInTheDocument();
    cleanup();

    setRequestCookies([
      ...(await signedInCookies()),
      { name: "smartman-tz", value: "America/Los_Angeles" },
    ]);
    await render(Decks, {});
    expect(screen.getByRole("heading", { name: "오늘 할 카드 19장" })).toBeInTheDocument();
    expect(rowNames()).toEqual(["Alpha, 카드 25장, 오늘 19", "Beta, 카드 1장"]);
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

  it("estimates the minutes from the user's review and first-answer paces, each answer counted up to 30 s", async () => {
    postgrest.seed("decks", deckRow("d-fr", "French"));
    postgrest.seed(
      "cards",
      ...["un", "deux", "trois"].map((front) => cardRow(`due-${front}`, "d-fr", front)),
      ...["quatre", "cinq", "six", "sept"].map((front) => cardRow(`new-${front}`, "d-fr", front)),
    );
    postgrest.seed(
      "card_states",
      ...["un", "deux", "trois"].map((front) => stateRow(`due-${front}`, due)),
    );
    // Yesterday, twenty cards first answered in 90 s, which counts 30, and reviewed in 24 s.
    const history = (reviews: number) =>
      Array.from({ length: 20 }, (_, index) => [
        reviewRow(`first-${String(index)}`, `h-${String(index)}`, start - day, 90_000),
        ...(index < reviews
          ? [reviewRow(`review-${String(index)}`, `h-${String(index)}`, start - day + 1000, 24_000)]
          : []),
      ]).flat();
    // Control: with 19 reviews the review pace is unknown, 10 s: 3 at 10 s and 4 at 30 s.
    postgrest.seed("reviews", ...history(19));
    await render(Decks, {});
    expect(screen.getByText("복습 3 · 새 카드 4 · 약 3분")).toBeInTheDocument();
    cleanup();

    // The twentieth review: 3 at 24 s and 4 at 30 s.
    postgrest.seed("reviews", ...history(20).slice(-1));
    await render(Decks, {});
    expect(screen.getByText("복습 3 · 새 카드 4 · 약 4분")).toBeInTheDocument();
  });

  it("reads the day's new cards as the day stood when it started, so answering its reviews leaves them", async () => {
    postgrest.seed("decks", deckRow("d-fr", "French"));
    const reviews = ["un", "deux", "trois", "quatre"];
    postgrest.seed(
      "cards",
      ...reviews.map((front) => cardRow(`due-${front}`, "d-fr", front)),
      ...Array.from({ length: 10 }, (_, index) =>
        cardRow(`new-${String(index)}`, "d-fr", `new ${String(index)}`),
      ),
    );
    postgrest.seed("card_states", ...reviews.map((front) => stateRow(`due-${front}`, due)));
    // Five study days before today of four cards each answered twice in 25 s, and each due
    // card's last answer.
    postgrest.seed(
      "reviews",
      ...[1, 2, 3, 4, 5].flatMap((days) =>
        [0, 1, 2, 3].flatMap((card) => [
          reviewRow(
            `h-${String(days)}-${String(card)}`,
            `h-${String(days)}-${String(card)}`,
            start - days * day,
            25_000,
          ),
          reviewRow(
            `h-${String(days)}-${String(card)}-r`,
            `h-${String(days)}-${String(card)}`,
            start - days * day + 60_000,
            25_000,
          ),
        ]),
      ),
      ...reviews.map((front) => reviewRow(`last-${front}`, `due-${front}`, due.lastReview, 6_000)),
    );
    await render(Decks, {});
    const before = /^복습 4 · 새 카드 (\d+) · /.exec(counts() ?? "")?.[1];
    // The figure is the user's own, short of the ten new cards the deck holds.
    expect(Number(before)).toBeGreaterThan(0);
    expect(Number(before)).toBeLessThan(10);
    cleanup();

    // Each review answered an hour ago, and now due in nine days.
    postgrest.seed(
      "reviews",
      ...reviews.map((front) =>
        reviewRow(`today-${front}`, `due-${front}`, start - 3_600_000, 6_000),
      ),
    );
    postgrest.rows.card_states = reviews.map((front) =>
      postgrest.rows.card_states.find((row) => row.card_id === `due-${front}`)
        ? { ...stateRow(`due-${front}`, notDue), revision: 0 }
        : {},
    );
    await render(Decks, {});

    expect(counts()).toMatch(new RegExp(`^복습 0 · 새 카드 ${String(before)} · `));
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
    const fronts = ["un", "deux", "trois"];
    postgrest.seed(
      "cards",
      ...fronts.map((front) => cardRow(`fr-${front}`, "d-fr", front)),
      ...fronts.map((front) => ({
        ...cardRow(`other-${front}`, "d-other", front),
        user_id: otherUser.id,
      })),
    );
    postgrest.seed(
      "card_states",
      ...fronts.map((front) => stateRow(`fr-${front}`, due)),
      ...fronts.map((front) => ({ ...stateRow(`other-${front}`, due), user_id: otherUser.id })),
    );
    // The other user's 40 answers of 25 s yesterday: one first answer and 39 reviews.
    postgrest.seed(
      "reviews",
      ...Array.from({ length: 40 }, (_, index) => ({
        ...reviewRow(`r-other-${String(index)}`, "other-un", start - day + index, 25_000),
        user_id: otherUser.id,
      })),
    );

    // Three reviews at the unknown pace, 10 s each.
    await render(Decks, {});
    expect(rowNames()).toEqual(["French, 카드 3장, 오늘 3"]);
    expect(screen.getByText("복습 3 · 새 카드 0 · 약 1분")).toBeInTheDocument();
    cleanup();

    // The other user's next request reads theirs, and nothing of the first user's: 3 at 25 s.
    setRequestCookies(await signedInCookies(otherUser));
    await render(Decks, {});
    expect(rowNames()).toEqual(["Other, 카드 3장, 오늘 3"]);
    expect(screen.getByText("복습 3 · 새 카드 0 · 약 2분")).toBeInTheDocument();
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

  it("with no card left today says the cards are done and links 계속 학습 to the study page over every deck, which opens on nothing to study or on the completion card", async () => {
    postgrest.seed("decks", deckRow("d-fr", "French"), deckRow("d-es", "Spanish"));
    postgrest.seed("cards", cardRow("fr-later", "d-fr", "oiseau"));
    postgrest.seed("card_states", stateRow("fr-later", notDue));
    // Answered yesterday: nothing was answered today.
    postgrest.seed("reviews", reviewRow("r-yesterday", "fr-later", start - day, 1_000));

    for (const answered of ["yesterday", "today"]) {
      if (answered === "today") {
        postgrest.seed("reviews", reviewRow("r-today", "fr-later", start - 3_600_000, 1_000));
      }
      await render(Decks, {});

      expect(
        screen.getByRole("heading", { name: "오늘 할 카드를 다 했어요" }),
        answered,
      ).toBeInTheDocument();
      expect(screen.queryByRole("link", { name: "모두 학습" }), answered).not.toBeInTheDocument();
      const href = screen.getByRole("link", { name: "계속 학습" }).getAttribute("href");
      expect(href, answered).toBe("/study?decks=d-fr,d-es");

      cleanup();
      await render(Study, {
        searchParams: Promise.resolve(Object.fromEntries(new URLSearchParams(href?.split("?")[1]))),
      });
      if (answered === "yesterday") {
        expect(screen.getByText("오늘은 학습할 카드가 없어요")).toBeInTheDocument();
      } else {
        expect(screen.getByRole("region", { name: "오늘 학습 완료" })).toBeInTheDocument();
      }
      cleanup();
    }
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
