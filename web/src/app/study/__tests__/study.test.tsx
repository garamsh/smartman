import { act, cleanup, fireEvent, screen, waitFor, within } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { afterEach, beforeAll, beforeEach, describe, expect, it, vi } from "vitest";
import { loadEngine } from "@/features/study";

import { cardRow, day, deckRow, reviewRow, seedDeck, start, stateRow } from "@/testing/library";
import { FakePostgrest } from "@/testing/mocks/postgrest";
import { server } from "@/testing/mocks/server";
import { setRequestCookies } from "@/testing/next-headers";
import { render } from "@/testing/render";
import { signedInCookies } from "@/testing/session";

import { Study } from "../_components/study";

// The study screen starts its session once the browser's engine has loaded; its first load
// compiles the module.
beforeAll(async () => {
  await loadEngine();
}, 30_000);

vi.mock("next/headers", () => import("@/testing/next-headers"));

const hour = 3_600_000;

/** Opens the study page over [decks] at [at], as the browser would with `?decks=`. */
async function open(decks: string, at = start) {
  vi.setSystemTime(at);
  await render(Study, { searchParams: Promise.resolve({ decks }) });
  // The screen starts its session once the browser's engine has loaded, under the skeleton.
  await waitFor(() => {
    expect(screen.queryByText("카드를 불러오는 중이에요.")).not.toBeInTheDocument();
  });
}

/** The front of the card on screen. */
const currentFront = () => screen.getByRole("group", { name: "문제" }).textContent;

/** The accessible names of this session's answers in the list beside the cards, oldest first. */
const stack = () =>
  within(screen.getByRole("complementary", { name: "이번 학습" }))
    .getAllByRole("button")
    .map((button) => button.getAttribute("aria-label"));

/** The cards column: the previous cards, as articles, and the current card. */
const cards = () => screen.getByRole("region", { name: "카드" });

/** The accessible names of the previous cards the column shows, top first. */
const shown = () =>
  within(cards())
    .queryAllByRole("article")
    .map((card) => card.getAttribute("aria-label"));

/** Answers every card shown with [key] until [count] cards have been shown; their fronts. */
/** The new cards a user's first study days take. */
const coldStartNewCards = 20;

/** [count] fronts, f00 onwards, created oldest first by `seedDeck`. */
function past(count: number): string[] {
  return Array.from({ length: count }, (_, index) => `f${String(index).padStart(2, "0")}`);
}

async function answerAll(key: string, count: number) {
  const user = userEvent.setup();
  const fronts: string[] = [];
  for (let shown = 0; shown < count; shown++) {
    fronts.push(currentFront());
    await user.keyboard(key);
  }
  return fronts;
}

describe("the study page", () => {
  let postgrest: FakePostgrest;
  beforeEach(async () => {
    vi.useFakeTimers({ toFake: ["Date"] });
    setRequestCookies(await signedInCookies());
    postgrest = new FakePostgrest();
    server.use(...postgrest.handlers);
  });
  afterEach(() => {
    vi.useRealTimers();
  });

  describe("queue", () => {
    const fronts = ["un", "deux", "trois", "quatre", "cinq", "six", "sept", "huit"];

    /**
     * Opens a session over a fresh copy of the deck at [at], so no write of an earlier session
     * changes what it studies.
     */
    async function openFresh(at = start) {
      cleanup();
      postgrest = new FakePostgrest();
      server.use(...postgrest.handlers);
      seedDeck(postgrest, "d1", fronts);
      await open("d1", at);
    }

    it("orders the cards by the session's seeded random source", async () => {
      await openFresh();
      const first = await answerAll("k", fronts.length);
      await openFresh();
      const again = await answerAll("k", fronts.length);
      // Control: a session started at another time draws another order.
      await openFresh(start + 1);
      const other = await answerAll("k", fronts.length);

      expect([...first].sort()).toEqual([...fronts].sort());
      expect(again).toEqual(first);
      expect(other).not.toEqual(first);
    });

    it("shows a card answered 모른다 again after 3 to 5 other cards, as the seed draws", async () => {
      const gaps: number[] = [];
      for (const at of [start, start]) {
        await openFresh(at);
        const [missed] = await answerAll("j", 1);
        const shown = await answerAll("k", fronts.length);
        gaps.push(missed === undefined ? -1 : shown.indexOf(missed));
      }

      expect(gaps[0]).toBeGreaterThanOrEqual(3);
      expect(gaps[0]).toBeLessThanOrEqual(5);
      expect(gaps[1]).toBe(gaps[0]);
    });

    it("studies the due cards and the 20 oldest new cards, and no card not yet due", async () => {
      const news = Array.from({ length: 25 }, (_, index) => `new ${String(index)}`);
      seedDeck(postgrest, "d1", news);
      postgrest.seed("cards", cardRow("due", "d1", "due"), cardRow("later", "d1", "later"));
      postgrest.seed(
        "card_states",
        stateRow("due", { stability: 3, difficulty: 5, lastReview: start - 4 * day, due: start }),
        stateRow("later", { stability: 9, difficulty: 5, lastReview: start, due: start + day }),
      );

      await open("d1");
      const shown = await answerAll("k", 21);

      expect(screen.getByRole("progressbar", { name: "진행" })).toHaveAttribute(
        "aria-valuemax",
        "21",
      );
      expect([...shown].sort()).toEqual(["due", ...news.slice(0, 20)].sort());
      expect(screen.getByRole("heading", { name: "오늘 학습 완료" })).toBeInTheDocument();
    });
  });

  describe("writing", () => {
    it("shows the next card before the answer's write is answered", async () => {
      seedDeck(postgrest, "d1", ["un", "deux"]);
      await open("d1");
      const first = currentFront();
      const release = postgrest.hold("reviews");

      await userEvent.setup().keyboard("k");

      expect(currentFront()).not.toBe(first);
      expect(stack()).toHaveLength(1);
      expect(postgrest.rows.reviews).toHaveLength(0);
      act(release);
      await waitFor(() => {
        expect(postgrest.rows.card_states).toHaveLength(1);
      });
      expect(postgrest.rows.reviews).toHaveLength(1);
    });

    it("says a write failed, keeps its answer, and sends it again on 다시 시도", async () => {
      seedDeck(postgrest, "d1", ["un", "deux", "trois"]);
      await open("d1");
      const user = userEvent.setup();
      const stop = postgrest.fail("reviews", 500);

      await user.keyboard("k");
      await user.keyboard("k");

      expect(await screen.findByRole("alert")).toHaveTextContent(
        "답을 저장하지 못했어요. 연결을 확인하고 다시 시도해 주세요.",
      );
      expect(stack()).toHaveLength(2);
      expect(postgrest.rows.reviews).toHaveLength(0);
      stop();
      await user.click(screen.getByRole("button", { name: "다시 시도" }));
      await waitFor(() => {
        expect(postgrest.rows.card_states).toHaveLength(2);
      });
      expect(postgrest.rows.reviews).toHaveLength(2);
      expect(screen.queryByRole("alert")).not.toBeInTheDocument();
    });
  });

  describe("today", () => {
    /** Seeds "d1" with "un" and "deux", new, and "trois", answered 모른다 this morning. */
    function seedToday() {
      seedDeck(postgrest, "d1", ["un", "deux"]);
      postgrest.seed("cards", cardRow("trois", "d1", "trois"));
      postgrest.seed(
        "card_states",
        stateRow("trois", {
          stability: 1,
          difficulty: 5,
          lastReview: start - hour,
          due: start + 2 * day,
        }),
      );
      postgrest.seed(
        "reviews",
        { ...reviewRow("r-today", "trois", start - hour, 90_000), rating: "again" },
        reviewRow("r-yesterday", "trois", start - day, 1_000),
      );
    }

    /** The completion card's line of counts, as read: its paragraph's text. */
    const completionLine = () =>
      screen.getByRole("region", { name: "오늘 학습 완료" }).querySelector("p")?.textContent;

    it("keeps a card answered 모른다 earlier today in today's list, and counts the day's cards done 안다", async () => {
      seedDeck(postgrest, "d1", ["un"]);
      postgrest.seed("cards", cardRow("deux", "d1", "deux"), cardRow("trois", "d1", "trois"));
      const tomorrow = { stability: 1, difficulty: 5, lastReview: start - hour, due: start + day };
      postgrest.seed("card_states", stateRow("deux", tomorrow), stateRow("trois", tomorrow));
      postgrest.seed(
        "reviews",
        // deux: 모른다 this morning, due tomorrow by its state; trois: 안다 this morning.
        { ...reviewRow("r-deux", "deux", start - hour, 1_000), rating: "again" },
        reviewRow("r-trois", "trois", start - hour, 1_000),
      );
      await open("d1");

      // trois is done; un, new, and deux, kept by today's list, are left.
      expect(screen.getByRole("progressbar")).toHaveAttribute("aria-valuenow", "1");
      expect(screen.getByText("1/3")).toBeInTheDocument();
      const user = userEvent.setup();
      const fronts = [currentFront()];
      await user.keyboard("k");
      fronts.push(currentFront());
      await user.keyboard("k");
      expect(fronts.sort()).toEqual(["deux", "un"]);
      expect(screen.getByText("3/3")).toBeInTheDocument();
    });

    it("reads the guide as going on with the day when a card of it is done, and as the day's start otherwise", async () => {
      seedDeck(postgrest, "d1", ["un"]);
      postgrest.seed("cards", cardRow("deux", "d1", "deux"));
      postgrest.seed(
        "card_states",
        stateRow("deux", {
          stability: 1,
          difficulty: 5,
          lastReview: start - hour,
          due: start + day,
        }),
      );
      postgrest.seed("reviews", reviewRow("r-deux", "deux", start - hour, 1_000));
      await open("d1");
      expect(screen.getByText(/^이어서 해요 · 남은 1장 · 약 \d+분$/)).toBeInTheDocument();
      cleanup();

      // Control: with nothing done today, the guide states the day's cards.
      postgrest.rows.reviews = [];
      await open("d1");
      expect(screen.getByText(/^오늘 \d+장 · 약 \d+분$/)).toBeInTheDocument();
      expect(screen.queryByText(/^이어서 해요/)).not.toBeInTheDocument();
    });

    it("shows the completion card in the current card's place, below the stack, once no card is left", async () => {
      seedToday();
      await open("d1");
      const user = userEvent.setup();
      // un and deux, new, and trois, answered 모른다 this morning, which today's list keeps until
      // it is answered 안다.
      await user.keyboard("k");
      await user.keyboard("k");
      expect(screen.getByRole("group", { name: "문제" })).toBeInTheDocument();
      await user.keyboard("k");

      expect(screen.queryByRole("group", { name: "문제" })).not.toBeInTheDocument();
      const completion = screen.getByRole("region", { name: "오늘 학습 완료" });
      const [previous] = within(cards()).getAllByRole("article");
      expect(previous?.compareDocumentPosition(completion)).toBe(Node.DOCUMENT_POSITION_FOLLOWING);
      expect(stack()).toHaveLength(3);
      // This morning's 모른다 and the session's three 안다; 90 s and the session's time, rounded
      // up; yesterday and today in a row.
      expect(completionLine()).toBe("3 안다1 모른다2분연속 2일");
      // No new card is left past today's, so the card says so and 그만하기 takes the focus.
      expect(screen.getByText("더 학습할 카드가 없어요")).toBeInTheDocument();
      expect(screen.queryByRole("button", { name: "학습하기" })).not.toBeInTheDocument();
      expect(screen.getByRole("link", { name: "그만하기" })).toHaveFocus();
      expect(screen.getByRole("link", { name: "그만하기" })).toHaveAttribute("href", "/");
    });

    it("reads the streak before today in one request and counts today's answer with it", async () => {
      seedDeck(postgrest, "d1", ["un"]);
      // Yesterday and the day before hold an answer; the day before that does not.
      postgrest.seed(
        "reviews",
        reviewRow("r-1", "d1-0", start - day, 1_000),
        reviewRow("r-2", "d1-0", start - 2 * day, 1_000),
        reviewRow("r-4", "d1-0", start - 4 * day, 1_000),
      );
      await open("d1");
      await userEvent.setup().keyboard("k");

      expect(completionLine()).toMatch(/연속 3일$/);
      expect(
        postgrest.requests.filter((request) => request === "POST rpc/study_streak_before"),
      ).toHaveLength(1);
      await waitFor(() => {
        expect(postgrest.rows.reviews).toHaveLength(4);
      });
    });

    it("goes on with the new cards past today's on 학습하기, oldest first, each answer written", async () => {
      const fronts = past(coldStartNewCards + 2);
      seedDeck(postgrest, "d1", fronts);
      await open("d1");
      await answerAll("k", coldStartNewCards);
      await waitFor(() => {
        expect(postgrest.rows.reviews).toHaveLength(coldStartNewCards);
      });
      const studyOn = screen.getByRole("button", { name: "학습하기" });
      expect(studyOn).toHaveFocus();
      const progress = screen.getByRole("progressbar", { name: "진행" });

      await userEvent.setup().click(studyOn);
      expect(await answerAll("k", 2)).toEqual(fronts.slice(coldStartNewCards));

      expect(screen.getByRole("progressbar", { name: "진행" })).toBe(progress);
      expect(progress.getAttribute("aria-valuetext")).toBe(
        `${String(coldStartNewCards + 2)}장 중 ${String(coldStartNewCards + 2)}장 끝냄`,
      );
      expect(screen.getByText("더 학습할 카드가 없어요")).toBeInTheDocument();
      await waitFor(() => {
        expect(postgrest.rows.reviews).toHaveLength(coldStartNewCards + 2);
      });
    });

    it("says there is nothing to study when no card is left and none was answered today", async () => {
      postgrest.seed("decks", deckRow("d1", "d1"));
      postgrest.seed("cards", cardRow("later", "d1", "later"));
      postgrest.seed(
        "card_states",
        stateRow("later", {
          stability: 9,
          difficulty: 5,
          lastReview: start - day,
          due: start + day,
        }),
      );
      postgrest.seed("reviews", reviewRow("r-yesterday", "later", start - day, 1_000));

      await open("d1");

      expect(screen.getByText("오늘은 학습할 카드가 없어요")).toBeInTheDocument();
      expect(screen.queryByRole("progressbar", { name: "진행" })).not.toBeInTheDocument();
      expect(screen.queryByRole("region", { name: "오늘 학습 완료" })).not.toBeInTheDocument();
      expect(screen.queryByRole("group", { name: "문제" })).not.toBeInTheDocument();

      // Control: the same card answered this morning opens on the completion card.
      cleanup();
      postgrest.seed("reviews", reviewRow("r-today", "later", start - hour, 1_000));
      await open("d1");
      expect(screen.getByRole("region", { name: "오늘 학습 완료" })).toBeInTheDocument();
      expect(screen.queryByText("오늘은 학습할 카드가 없어요")).not.toBeInTheDocument();
    });
  });

  describe("cards", () => {
    const fronts = ["un", "deux", "trois", "quatre", "cinq"];

    /** Answers the first three cards 안다, 모른다 and 안다; their fronts. */
    async function answerThree() {
      const user = userEvent.setup();
      const answered: string[] = [];
      for (const key of ["k", "j", "k"]) {
        answered.push(currentFront());
        await user.keyboard(key);
      }
      return answered;
    }

    const label = (front: string, answer: string) =>
      `앞면: ${front}. 뒷면: ${front} back. 답: ${answer}`;

    /** Touches the previous card at (200, 100), moves to each of [moves] [step] ms apart, lifts. */
    function swipe(card: HTMLElement, moves: [number, number][], step = 1) {
      const from: [number, number] = [200, 100];
      const [x, y] = from;
      fireEvent.pointerDown(card, { pointerId: 1, pointerType: "touch", clientX: x, clientY: y });
      let at: [number, number] = from;
      for (const move of moves) {
        vi.setSystemTime(Date.now() + step);
        at = move;
        fireEvent.pointerMove(card, {
          pointerId: 1,
          pointerType: "touch",
          clientX: move[0],
          clientY: move[1],
        });
      }
      fireEvent.pointerUp(card, {
        pointerId: 1,
        pointerType: "touch",
        clientX: at[0],
        clientY: at[1],
      });
    }

    /** The previous card on screen. */
    const previousCard = () => within(cards()).getByRole("article");

    it("shows exactly the previous card and the current card, in two rows of one height", async () => {
      seedDeck(postgrest, "d1", fronts);
      await open("d1");
      const [, , third] = await answerThree();

      expect(shown()).toEqual([label(third ?? "", "안다")]);
      const current = within(cards()).getByRole("region", { name: "현재 카드" });
      // Both in one grid whose rows share the tallest one's height.
      expect(current.parentElement).toBe(previousCard().parentElement);
      expect(current.parentElement?.className).toContain("auto-rows-fr");
      // Both sides at the current card's sizes.
      expect(within(previousCard()).getByText(third ?? "").parentElement?.className).toContain(
        "text-question",
      );
      expect(
        within(previousCard()).getByText(`${third ?? ""} back`).parentElement?.className,
      ).toContain("text-answer");
      // Control: the list beside holds all three.
      expect(stack()).toHaveLength(3);
    });

    it("reaches no earlier card with ↑, ↓, the wheel or a vertical drag, and ← and → answer the current card alone", async () => {
      seedDeck(postgrest, "d1", fronts);
      await open("d1");
      const [, , third] = await answerThree();
      const user = userEvent.setup();
      const rest = [label(third ?? "", "안다")];
      const current = currentFront();

      await user.keyboard("{ArrowUp}");
      fireEvent.wheel(cards(), { deltaY: -300 });
      swipe(previousCard(), [
        [200, 200],
        [200, 400],
      ]);
      await user.keyboard("{ArrowDown}");
      expect(shown()).toEqual(rest);
      expect(currentFront()).toBe(current);
      expect(screen.queryByRole("button", { name: "지금 카드로" })).not.toBeInTheDocument();

      await user.keyboard("{ArrowLeft}");
      expect(currentFront()).not.toBe(current);
      expect(stack()).toHaveLength(4);
      expect(shown()).toEqual([label(current, "모른다")]);
      expect(stack()[2]).toBe(label(third ?? "", "안다"));
    });

    it("opens the previous card whole on a click, and closes it on 닫기 or Esc with the focus back on the card", async () => {
      seedDeck(postgrest, "d1", fronts);
      await open("d1");
      const [, , third] = await answerThree();
      const user = userEvent.setup();
      const open_ = within(previousCard()).getByRole("button", { name: "카드 전체 보기" });

      await user.click(open_);
      let detail = screen.getByRole("dialog", { name: "카드" });
      expect(within(detail).getByText(third ?? "")).toBeInTheDocument();
      expect(within(detail).getByText(`${third ?? ""} back`)).toBeInTheDocument();
      expect(within(detail).getByText("답: 안다")).toBeInTheDocument();
      expect(within(detail).getByRole("button", { name: "닫기" })).toHaveFocus();
      // The answer is changed by a swipe or Z, not from here.
      expect(within(detail).getAllByRole("button")).toHaveLength(1);
      await user.click(within(detail).getByRole("button", { name: "닫기" }));
      expect(screen.queryByRole("dialog")).not.toBeInTheDocument();
      expect(open_).toHaveFocus();

      await user.click(open_);
      detail = screen.getByRole("dialog", { name: "카드" });
      // Keys belong to the dialog while it is open: → answers nothing.
      const current = currentFront();
      await user.keyboard("{ArrowRight}");
      expect(currentFront()).toBe(current);
      await user.keyboard("{Escape}");
      expect(screen.queryByRole("dialog")).not.toBeInTheDocument();
      expect(open_).toHaveFocus();
      expect(shown()).toEqual([label(third ?? "", "안다")]);
    });

    it("changes the previous card's answer on a touch swipe past 100 or a fling toward the other answer, and writes the replay", async () => {
      seedDeck(postgrest, "d1", fronts);
      await open("d1");
      const [, , third] = await answerThree();
      await waitFor(() => {
        expect(postgrest.rows.reviews).toHaveLength(3);
      });
      const current = currentFront();

      // Toward 안다, the answer it has: nothing changes.
      swipe(previousCard(), [
        [260, 100],
        [400, 100],
      ]);
      expect(shown()).toEqual([label(third ?? "", "안다")]);
      // Short of 100 and slow, toward 모른다: nothing changes.
      swipe(
        previousCard(),
        [
          [190, 100],
          [180, 100],
          [170, 100],
          [160, 100],
          [150, 100],
          [140, 100],
          [130, 100],
          [120, 100],
        ],
        100,
      );
      expect(shown()).toEqual([label(third ?? "", "안다")]);
      // Control: past 100 toward 모른다, it changes, and the current card stays.
      vi.setSystemTime(start + 60_000);
      swipe(previousCard(), [
        [150, 100],
        [80, 100],
      ]);
      expect(shown()).toEqual([`${label(third ?? "", "모른다")}. 수정됨`]);
      expect(currentFront()).toBe(current);
      await waitFor(() => {
        expect(postgrest.rows.reviews.filter((row) => row.rating === "again")).toHaveLength(2);
      });
      expect(postgrest.rows.reviews).toHaveLength(3);

      // A fling: 40 in a millisecond, toward 안다.
      swipe(previousCard(), [
        [210, 100],
        [250, 100],
      ]);
      expect(shown()).toEqual([label(third ?? "", "안다")]);
    });

    it("shows the answer a swipe would give behind the previous card, and no detail opens when it ends", async () => {
      seedDeck(postgrest, "d1", fronts);
      await open("d1");
      await answerThree();
      const card = previousCard();

      fireEvent.pointerDown(card, {
        pointerId: 1,
        pointerType: "touch",
        clientX: 200,
        clientY: 100,
      });
      fireEvent.pointerMove(card, {
        pointerId: 1,
        pointerType: "touch",
        clientX: 150,
        clientY: 100,
      });
      expect(within(card).getByText("모른다로 바꿔요")).toBeInTheDocument();
      const face = within(card).getByRole("button", { name: "카드 전체 보기" });
      expect(face.style.transform).toContain("translateX(-50px)");
      vi.setSystemTime(Date.now() + 500);
      fireEvent.pointerUp(card, { pointerId: 1, pointerType: "touch", clientX: 150, clientY: 100 });
      fireEvent.click(face);
      expect(screen.queryByRole("dialog")).not.toBeInTheDocument();
      expect(within(card).queryByText("모른다로 바꿔요")).not.toBeInTheDocument();
      expect(face.style.transform).toContain("translateX(0px)");
    });

    it("grades the previous card by its fill, its line and a chip naming the answer", async () => {
      seedDeck(postgrest, "d1", fronts);
      await open("d1");
      const user = userEvent.setup();

      for (const [key, answer, fill, line, chip] of [
        ["k", "안다", "bg-know-card", "border-know-line", "bg-know"],
        ["j", "모른다", "bg-dont-know-card", "border-dont-know-line", "bg-dont-know-text"],
      ] as const) {
        const front = currentFront();
        await user.keyboard(key);
        expect(previousCard()).toHaveAccessibleName(label(front, answer));
        const face = within(previousCard()).getByRole("button", { name: "카드 전체 보기" });
        expect(face.className).toContain(fill);
        expect(face.className).toContain(line);
        const word = within(previousCard()).getByText(answer);
        expect(word.className).toContain(chip);
        expect(word.querySelector("svg")).not.toBeNull();
      }
    });

    it("shows the session's guide with its size in the previous card's place from its start until its first answer, for every user", async () => {
      const guide = () => screen.queryByRole("region", { name: "학습 안내" });
      seedDeck(postgrest, "d1", ["un", "deux"]);
      // A user with an answer stored before today: the guide is not the first session's alone.
      postgrest.seed("cards", cardRow("old", "d2", "old"));
      postgrest.seed("reviews", reviewRow("r-old", "old", start - 3 * day, 1_000));
      await open("d1");

      expect(guide()).toBeInTheDocument();
      const shownGuide = guide() ?? document.body;
      // Two new cards at the unknown pace, 10 s each: about a minute.
      expect(within(shownGuide).getByText("오늘 2장 · 약 1분")).toBeInTheDocument();
      expect(
        within(shownGuide)
          .getAllByRole("listitem")
          .map((item) => item.textContent),
      ).toEqual([
        "알면 안다(→), 모르면 모른다(←)를 눌러요",
        "답한 카드는 뜻과 함께 여기로 올라와요. 밀어서 바꿀 수 있어요",
      ]);
      const user = userEvent.setup();
      await user.keyboard("j");
      expect(guide()).not.toBeInTheDocument();
      expect(shown()).toHaveLength(1);
      // A "모른다" puts its card back; the guide does not return.
      await user.keyboard("k");
      expect(guide()).not.toBeInTheDocument();
    });

    it("opens straight on the new cards past today's when none is left today, under the guide saying today's cards are done, until its first answer", async () => {
      // The first day's new cards answered this morning, and two more.
      const fronts = past(coldStartNewCards + 2);
      seedDeck(postgrest, "d1", fronts);
      for (let index = 0; index < coldStartNewCards; index++) {
        postgrest.seed(
          "card_states",
          stateRow(`d1-${String(index)}`, {
            stability: 1,
            difficulty: 5,
            lastReview: start - hour,
            due: start + 2 * day,
          }),
        );
        postgrest.seed(
          "reviews",
          reviewRow(`r-${String(index)}`, `d1-${String(index)}`, start - hour, 1_000),
        );
      }
      await open("d1");

      expect(screen.queryByRole("region", { name: "오늘 학습 완료" })).not.toBeInTheDocument();
      expect(currentFront()).toBe(fronts[coldStartNewCards]);
      const guide = screen.getByRole("region", { name: "학습 안내" });
      expect(
        within(guide).getByText("오늘 할 카드를 다 했어요", { exact: true }),
      ).toBeInTheDocument();
      expect(within(guide).queryByText(/오늘 \d+장/)).not.toBeInTheDocument();
      expect(within(guide).getAllByRole("listitem")).toHaveLength(2);

      await userEvent.setup().keyboard("k");
      expect(currentFront()).toBe(fronts[coldStartNewCards + 1]);
      expect(screen.queryByRole("region", { name: "학습 안내" })).not.toBeInTheDocument();
    });

    it("springs the previous card back only under prefers-reduced-motion: no-preference", async () => {
      seedDeck(postgrest, "d1", fronts);
      await open("d1");
      await answerThree();

      const face = within(previousCard()).getByRole("button", { name: "카드 전체 보기" });
      expect(face.className.split(" ").filter((name) => name.includes("transition"))).toEqual([
        "motion-safe:transition-transform",
      ]);
    });
  });

  describe("keyboard", () => {
    beforeEach(async () => {
      seedDeck(postgrest, "d1", ["un", "deux", "trois", "quatre", "cinq"]);
      await open("d1");
    });

    it("shows the current card's question alone, with no answer to reveal, on Space or otherwise", async () => {
      const card = screen.getByRole("region", { name: "현재 카드" });
      const front = currentFront();
      // The card holds one of the seeded fronts and nothing else.
      expect(["un", "deux", "trois", "quatre", "cinq"]).toContain(card.textContent);
      expect(card).not.toHaveTextContent(`${front} back`);
      expect(screen.queryByRole("group", { name: "답" })).not.toBeInTheDocument();
      expect(screen.queryByRole("button", { name: "답 보기" })).not.toBeInTheDocument();

      await userEvent.setup().keyboard(" ");

      expect(card).not.toHaveTextContent(`${front} back`);
      expect(currentFront()).toBe(front);
      // Control: the answer shows once answered, on the previous card.
      await userEvent.setup().keyboard("k");
      expect(stack()).toEqual([`앞면: ${front}. 뒷면: ${front} back. 답: 안다`]);
    });

    it.each([
      ["→", "{ArrowRight}", "안다"],
      ["K", "k", "안다"],
      ["←", "{ArrowLeft}", "모른다"],
      ["J", "j", "모른다"],
    ])("answers with %s", async (_name, key, answer) => {
      const front = currentFront();

      await userEvent.setup().keyboard(key);

      expect(stack()).toEqual([`앞면: ${front}. 뒷면: ${front} back. 답: ${answer}`]);
      expect(currentFront()).not.toBe(front);
    });

    it("toggles the last answer on Z or 마지막 답 바꾸기, shown at every width", async () => {
      const user = userEvent.setup();
      await user.keyboard("k");
      await user.keyboard("j");

      await user.keyboard("z");

      expect(stack()[0]).toMatch(/답: 안다$/);
      expect(stack()[1]).toMatch(/답: 안다. 수정됨$/);
      const toggle = screen.getByRole("button", { name: "마지막 답 바꾸기" });
      expect(toggle.className.split(" ")).not.toContain("hidden");
      await user.click(toggle);
      expect(stack()[1]).toMatch(/답: 모른다$/);
    });

    it("leaves for the deck list on Esc", async () => {
      const user = userEvent.setup();
      const close = screen.getByRole("link", { name: "끝내기" });
      const followed = vi.fn();
      close.addEventListener("click", (event) => {
        event.preventDefault();
        followed();
      });
      await user.keyboard("k");

      await user.keyboard("{Escape}");

      expect(close).toHaveAttribute("href", "/");
      expect(followed).toHaveBeenCalledOnce();
    });

    it("lists every shortcut on ?, and closes the list on Esc without ending the session", async () => {
      const user = userEvent.setup();

      await user.keyboard("?");

      const help = screen.getByRole("dialog", { name: "단축키" });
      for (const action of ["안다", "모른다", "마지막 답 바꾸기", "학습 끝내기", "단축키 보기"]) {
        expect(within(help).getByText(action)).toBeInTheDocument();
      }
      await user.keyboard("{Escape}");
      expect(screen.queryByRole("dialog")).not.toBeInTheDocument();
      expect(screen.getByRole("group", { name: "문제" })).toBeInTheDocument();
    });

    it("mirrors each shortcut with a visible control", async () => {
      await userEvent.setup().keyboard("k");

      const controls = Object.fromEntries(
        ["안다", "모른다", "마지막 답 바꾸기", "끝내기", "단축키"].map((name) => [
          name,
          screen
            .getByRole(name === "끝내기" ? "link" : "button", { name })
            .getAttribute("aria-keyshortcuts"),
        ]),
      );

      expect(controls).toEqual({
        안다: "ArrowRight K",
        모른다: "ArrowLeft J",
        "마지막 답 바꾸기": "Z",
        끝내기: "Escape",
        단축키: "?",
      });
    });
  });
});
