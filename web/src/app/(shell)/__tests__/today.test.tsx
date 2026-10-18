import { cleanup, screen, waitFor, within } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { afterEach, beforeAll, beforeEach, describe, expect, it, vi } from "vitest";
import { loadEngine } from "@/features/study";

import { FakePostgrest } from "@/testing/mocks/postgrest";
import { otherUser, testUser } from "@/testing/mocks/handlers";
import { server } from "@/testing/mocks/server";
import { cardRow, day, deckRow, reviewRow, start, stateRow } from "@/testing/library";
import { setRequestCookies } from "@/testing/next-headers";
import { render } from "@/testing/render";
import { signedInCookies } from "@/testing/session";

import { Study } from "../../study/_components/study";
import { Today } from "../_components/today";
import { Decks } from "../decks/_components/decks";

/** The 오늘 page's content and the 덱 page's, rendered one after the other. */
const renderBoth = () =>
  render(
    async () => (
      <>
        {await Today()}
        {await Decks()}
      </>
    ),
    {},
  );

// The study screen starts its session once the browser's engine has loaded; its first load
// compiles the module.
beforeAll(async () => {
  await loadEngine();
}, 30_000);

vi.mock("next/headers", () => import("@/testing/next-headers"));

const due = { stability: 3, difficulty: 5, lastReview: start - 4 * day, due: start - day };
const notDue = { stability: 30, difficulty: 5, lastReview: start - day, due: start + 9 * day };

describe("the 오늘 and 덱 pages", () => {
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
  const deckList = () => within(screen.getByRole("region", { name: "덱 목록" }));
  const row = (name: string) =>
    deckList().getByRole("link", { name: new RegExp(`^${name}, 카드`) });
  /** The today card's count and minutes, as its heading reads them: "n 장 · 약 m분". */
  const todayLine = () => document.getElementById("today-title")?.textContent;
  /** The deck rows' names, without the progress each ends with. */
  const rowNames = () =>
    deckList()
      .getAllByRole("link")
      .map((link) => link.getAttribute("aria-label")?.replace(/, \d+장 중 \d+장 익힘$/, ""));

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

    await renderBoth();

    expect(screen.getByRole("heading", { name: "오늘 할 카드 2장" })).toBeInTheDocument();
    expect(todayLine()).toBe("2 장 · 약 1분");
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
    await renderBoth();
    expect(screen.getByRole("heading", { name: "오늘 할 카드 20장" })).toBeInTheDocument();
    cleanup();

    setRequestCookies([
      ...(await signedInCookies()),
      { name: "smartman-tz", value: "America/Los_Angeles" },
    ]);
    await renderBoth();
    expect(screen.getByRole("heading", { name: "오늘 할 카드 19장" })).toBeInTheDocument();
    expect(rowNames()).toEqual(["Alpha, 카드 25장, 오늘 19", "Beta, 카드 1장"]);
  });

  it("says in the header that new cards wait while more than three days of reviews are due", async () => {
    const paused = "밀린 복습을 마칠 때까지 새 카드는 쉬어요.";
    postgrest.seed("decks", deckRow("d-fr", "French"));
    postgrest.seed("cards", cardRow("fr-new", "d-fr", "chat"), cardRow("fr-due", "d-fr", "chien"));
    postgrest.seed("card_states", stateRow("fr-due", due));
    // Control: one card due every three days is not a backlog.
    await renderBoth();
    expect(todayLine()).toBe("2 장 · 약 1분");
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
    await renderBoth();

    expect(screen.getByRole("heading", { name: "오늘 할 카드 3장" })).toBeInTheDocument();
    expect(todayLine()).toBe("3 장 · 약 1분");
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

    await renderBoth();

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

    await renderBoth();

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
    await renderBoth();
    expect(todayLine()).toBe("7 장 · 약 3분");
    cleanup();

    // The twentieth review: 3 at 24 s and 4 at 30 s.
    postgrest.seed("reviews", ...history(20).slice(-1));
    await renderBoth();
    expect(todayLine()).toBe("7 장 · 약 4분");
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
    await renderBoth();
    // The four reviews due and the day's new cards; the line goes on with the minutes, which the
    // paces set.
    const before = Number(/^(\d+) 장/.exec(todayLine() ?? "")?.[1]) - 4;
    // The figure is the user's own, short of the ten new cards the deck holds.
    expect(before).toBeGreaterThan(0);
    expect(before).toBeLessThan(10);
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
    await renderBoth();

    // The reviews are done; the new cards stand as the day started.
    expect(todayLine()).toMatch(new RegExp(`^${String(before)} 장 · `));
  });

  it("says a card is unreadable when an earlier answer to a card answered today names it by no string", async () => {
    const unreadable =
      "이 앱이 읽을 수 없는 카드가 있어 불러오지 못했어요. 휴대폰 앱에서 카드를 확인해 주세요.";
    postgrest.seed("decks", deckRow("d-fr", "French"));
    postgrest.seed("cards", cardRow("fr", "d-fr", "chat"));
    postgrest.seed("reviews", reviewRow("today", "fr", start - 3_600_000, 6_000));
    // Control: an earlier answer naming the card by its id is read.
    postgrest.seed("reviews", reviewRow("before", "fr", start - 2 * day, 6_000));
    await render(Today, {});
    expect(screen.getByRole("heading", { name: "오늘 할 카드 1장" })).toBeInTheDocument();
    expect(screen.queryByText(unreadable)).not.toBeInTheDocument();
    cleanup();

    // The same answer with its card id held as a list, which the card filter still matches.
    postgrest.rows.reviews = postgrest.rows.reviews.map((row) =>
      row.id === "before" ? { ...row, card_id: ["fr"] } : row,
    );
    await render(Today, {});

    expect(screen.getByText(unreadable)).toBeInTheDocument();
  });

  it("marks a deck its owner published with 공개, and no other", async () => {
    postgrest.seed("decks", deckRow("d-fr", "French", false, "public"), deckRow("d-es", "Spanish"));
    postgrest.seed("cards", cardRow("fr", "d-fr", "chat"), cardRow("es", "d-es", "gato"));

    await renderBoth();

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
    await renderBoth();
    expect(rowNames()).toEqual(["French, 카드 3장, 오늘 3"]);
    expect(todayLine()).toBe("3 장 · 약 1분");
    cleanup();

    // The other user's next request reads theirs, and nothing of the first user's: 3 at 25 s.
    setRequestCookies(await signedInCookies(otherUser));
    await renderBoth();
    expect(rowNames()).toEqual(["Other, 카드 3장, 오늘 3"]);
    expect(todayLine()).toBe("3 장 · 약 2분");
  });

  it("carries no account content: neither the email nor 로그아웃", async () => {
    postgrest.seed("decks", deckRow("d-fr", "French"));

    await renderBoth();

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

    await render(Today, {});

    expect(screen.getByRole("alert")).toHaveTextContent(
      "서버에 연결할 수 없어요. 연결을 확인하고 다시 시도해 주세요.",
    );
  });

  it("with no card left today says the cards are done and links 학습하기 to the study page over every deck, which opens on nothing to study or on the completion card", async () => {
    postgrest.seed("decks", deckRow("d-fr", "French"), deckRow("d-es", "Spanish"));
    postgrest.seed("cards", cardRow("fr-later", "d-fr", "oiseau"));
    postgrest.seed("card_states", stateRow("fr-later", notDue));
    // Answered yesterday: nothing was answered today.
    postgrest.seed("reviews", reviewRow("r-yesterday", "fr-later", start - day, 1_000));

    for (const answered of ["yesterday", "today"]) {
      if (answered === "today") {
        postgrest.seed("reviews", reviewRow("r-today", "fr-later", start - 3_600_000, 1_000));
      }
      await render(Today, {});

      expect(
        screen.getByRole("heading", { name: "오늘 할 카드를 다 했어요" }),
        answered,
      ).toBeInTheDocument();
      expect(screen.queryByRole("link", { name: "모두 학습" }), answered).not.toBeInTheDocument();
      const href = screen.getByRole("link", { name: "학습하기" }).getAttribute("href");
      expect(href, answered).toBe("/study?decks=d-fr,d-es");

      cleanup();
      await render(Study, {
        searchParams: Promise.resolve(Object.fromEntries(new URLSearchParams(href?.split("?")[1]))),
      });
      // The study screen starts once the browser's engine has loaded, under the skeleton.
      await waitFor(() => {
        expect(screen.queryByText("카드를 불러오는 중이에요.")).not.toBeInTheDocument();
      });
      if (answered === "yesterday") {
        expect(screen.getByText("오늘은 학습할 카드가 없어요")).toBeInTheDocument();
      } else {
        expect(screen.getByRole("region", { name: "오늘 학습 완료" })).toBeInTheDocument();
      }
      cleanup();
    }
  });

  it("shows the goal ring, the streak and where the user stands, from the shared definitions", async () => {
    postgrest.seed("decks", deckRow("d-fr", "French"));
    postgrest.seed(
      "cards",
      ...["a", "b", "c", "d"].map((front) => cardRow(`new-${front}`, "d-fr", front)),
      ...["e", "f"].map((front) => cardRow(`done-${front}`, "d-fr", front)),
    );
    // Two cards first answered an hour ago, due again in nine days: 2 of a goal of 6 done.
    postgrest.seed("card_states", ...["e", "f"].map((front) => stateRow(`done-${front}`, notDue)));
    postgrest.seed(
      "reviews",
      ...["e", "f"].map((front) =>
        reviewRow(`r-${front}`, `done-${front}`, start - 3_600_000, 6_000),
      ),
    );
    await render(Today, {});

    expect(screen.getByRole("img", { name: "하루 목표 6장 중 2장" })).toBeInTheDocument();
    expect(screen.getByText("1일 연속")).toBeInTheDocument();
    expect(screen.getByText("좋은 출발이에요")).toBeInTheDocument();
    cleanup();

    // Nothing answered today, after two study days in a row: the streak is the line.
    postgrest.rows.reviews = ["e", "f"].map((front, index) =>
      reviewRow(`r-${front}`, `done-${front}`, start - (index + 1) * day, 6_000),
    );
    await render(Today, {});

    expect(screen.getByRole("img", { name: "하루 목표 4장 중 0장" })).toBeInTheDocument();
    expect(screen.getByText("2일 연속")).toBeInTheDocument();
    expect(screen.getByText("2일째 이어 가는 중이에요")).toBeInTheDocument();
  });

  it("forecasts the next seven days by study day, today's load first", async () => {
    postgrest.seed("decks", deckRow("d-fr", "French"));
    postgrest.seed("cards", ...["a", "b", "c"].map((front) => cardRow(front, "d-fr", front)));
    // Thursday 15 January 2026 in Seoul: two cards due tomorrow, one on Sunday.
    postgrest.seed(
      "card_states",
      stateRow("a", { stability: 3, difficulty: 5, lastReview: start - day, due: start + day }),
      stateRow("b", { stability: 3, difficulty: 5, lastReview: start - day, due: start + day }),
      stateRow("c", { stability: 9, difficulty: 5, lastReview: start - day, due: start + 3 * day }),
    );
    await render(Today, {});

    expect(screen.getByRole("heading", { name: "오늘 할 카드를 다 했어요" })).toBeInTheDocument();
    expect(
      screen.getByRole("img", {
        name: "오늘 0장, 내일 2장, 토 0장, 일 1장, 월 0장, 화 0장, 수 0장",
      }),
    ).toBeInTheDocument();
    expect(screen.getByText("이번 주 3장")).toBeInTheDocument();
    expect(screen.getByRole("heading", { name: "오늘" })).toBeInTheDocument();
    expect(screen.getByText("1월 15일 목요일")).toBeInTheDocument();
  });

  it("lists the decks with cards left today, each opening a session over it, and no other", async () => {
    postgrest.seed("decks", deckRow("d-fr", "French"), deckRow("d-es", "Spanish"));
    postgrest.seed(
      "cards",
      cardRow("fr-new", "d-fr", "chat"),
      cardRow("fr-due", "d-fr", "chien"),
      cardRow("es-later", "d-es", "gato"),
    );
    postgrest.seed("card_states", stateRow("fr-due", due), stateRow("es-later", notDue));
    await render(Today, {});

    const decks = within(screen.getByRole("region", { name: "오늘 할 덱" }));
    expect(decks.getAllByRole("link").map((link) => link.getAttribute("aria-label"))).toEqual([
      "French, 오늘 2장 학습",
    ]);
    expect(decks.getByRole("link", { name: "French, 오늘 2장 학습" })).toHaveAttribute(
      "href",
      "/study?decks=d-fr",
    );
  });

  it("opens 모두 학습 on Enter from the page, but not from a control", async () => {
    postgrest.seed("decks", deckRow("d-fr", "French"));
    postgrest.seed("cards", cardRow("fr-new", "d-fr", "chat"));
    await render(Today, {});
    const study = screen.getByRole("link", { name: "모두 학습" });
    const clicked = vi.spyOn(study, "click").mockImplementation(() => undefined);
    const user = userEvent.setup();

    expect(study).toHaveAttribute("aria-keyshortcuts", "Enter");
    // Control: Enter on another link is that link's own.
    within(screen.getByRole("region", { name: "오늘 할 덱" }))
      .getByRole("link")
      .focus();
    await user.keyboard("{Enter}");
    expect(clicked).not.toHaveBeenCalled();
    (document.activeElement as HTMLElement | null)?.blur();
    await user.keyboard("{Enter}");
    expect(clicked).toHaveBeenCalledOnce();
  });

  it("shows the last 30 study days' retention against the 90% target with its gap, linking to the record page, and a sentence without a review", async () => {
    postgrest.seed("decks", deckRow("d-fr", "French"));
    postgrest.seed(
      "cards",
      cardRow("a", "d-fr", "chat"),
      cardRow("b", "d-fr", "chien"),
      cardRow("c", "d-fr", "oiseau"),
    );
    const answer = (id: string, card: string, ago: number, rating: "good" | "again") => ({
      ...reviewRow(id, card, start - ago, 4_000),
      rating,
    });
    // First answers alone hold no scheduled review.
    postgrest.seed(
      "reviews",
      answer("a1", "a", 10 * day, "good"),
      answer("b1", "b", 10 * day, "good"),
    );
    await render(Today, {});
    const card = () => within(screen.getByRole("region", { name: "기억률" }));
    expect(card().getByText("최근 30일 동안 복습한 카드가 없어요.")).toBeInTheDocument();
    expect(card().getByRole("link", { name: "기록에서 자세히 보기" })).toHaveAttribute(
      "href",
      "/record",
    );
    cleanup();

    // a's "안다" and b's "모른다" 5 days back are scheduled; c's "모른다" 45 days back is outside
    // the 30 days.
    postgrest.seed(
      "reviews",
      answer("a2", "a", 5 * day, "good"),
      answer("b2", "b", 5 * day, "again"),
      answer("c0", "c", 60 * day, "good"),
      answer("c-old", "c", 45 * day, "again"),
    );
    await render(Today, {});
    expect(card().getByText("50%")).toBeInTheDocument();
    expect(card().getByText("목표 90%")).toBeInTheDocument();
    expect(card().getByText("목표보다 40%p 낮아요")).toBeInTheDocument();
    expect(card().getByRole("img").getAttribute("aria-label")).toBe(
      "최근 30일 복습에서 맞힌 비율, 목표 90%: 1월 10일 50%",
    );
    expect(card().getByRole("link", { name: "기록에서 자세히 보기" })).toHaveAttribute(
      "href",
      "/record",
    );
  });

  it("shows the first-run invitation in place of the today card on 오늘 and of the list on 덱 when there is no deck", async () => {
    const title = "첫 덱을 만들어 볼까요?";
    const pointer =
      "덱은 휴대폰 앱에서 만들어요. 단어장 사진을 찍거나 직접 입력하면 여기에도 보여요.";
    // Control: a user with one deck sees the today card and the list, and no invitation.
    postgrest.seed("decks", deckRow("d-fr", "French"));
    await renderBoth();
    expect(screen.getByRole("heading", { name: "내 덱 1" })).toBeInTheDocument();
    expect(screen.getByRole("heading", { name: "오늘 할 카드를 다 했어요" })).toBeInTheDocument();
    expect(screen.queryByRole("heading", { name: title })).not.toBeInTheDocument();
    cleanup();

    postgrest = new FakePostgrest();
    server.use(...postgrest.handlers);
    for (const page of [Today, Decks]) {
      await render(page, {});

      expect(screen.getByRole("heading", { name: title })).toBeInTheDocument();
      expect(screen.getByText(pointer)).toBeInTheDocument();
      expect(screen.queryByRole("heading", { name: /^오늘 할 카드/ })).not.toBeInTheDocument();
      expect(screen.queryByRole("region", { name: "덱 목록" })).not.toBeInTheDocument();
      // The web creates nothing and has no public-deck browsing, so the invitation offers no
      // action.
      expect(screen.queryByRole("link")).not.toBeInTheDocument();
      expect(screen.queryByRole("button")).not.toBeInTheDocument();
      cleanup();
    }
  });
});
