import { act, cleanup, fireEvent, screen, waitFor, within } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";

import { cardRow, day, deckRow, reviewRow, seedDeck, start, stateRow } from "@/testing/library";
import { FakePostgrest } from "@/testing/mocks/postgrest";
import { server } from "@/testing/mocks/server";
import { setRequestCookies } from "@/testing/next-headers";
import { render } from "@/testing/render";
import { signedInCookies } from "@/testing/session";

import { Study } from "../_components/study";

vi.mock("next/headers", () => import("@/testing/next-headers"));

const hour = 3_600_000;

/** Opens the study page over [decks] at [at], as the browser would with `?decks=`. */
async function open(decks: string, at = start) {
  vi.setSystemTime(at);
  await render(Study, { searchParams: Promise.resolve({ decks }) });
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

    it("shows the completion card in the current card's place, below the stack, once no card is left", async () => {
      seedToday();
      await open("d1");
      const user = userEvent.setup();
      await user.keyboard("k");
      await user.keyboard("k");

      expect(screen.queryByRole("group", { name: "문제" })).not.toBeInTheDocument();
      const completion = screen.getByRole("region", { name: "오늘 학습 완료" });
      const [previous] = within(cards()).getAllByRole("article");
      expect(previous?.compareDocumentPosition(completion)).toBe(Node.DOCUMENT_POSITION_FOLLOWING);
      expect(stack()).toHaveLength(2);
      // This morning's 모른다 and the session's two 안다; 90 s and the session's time, rounded
      // up; yesterday and today in a row.
      expect(completionLine()).toBe("2 안다1 모른다2분연속 2일");
      expect(screen.getByRole("button", { name: "계속 학습" })).toHaveFocus();
      expect(screen.getByRole("link", { name: "그만하기" })).toHaveAttribute("href", "/");
    });

    it("goes on as practice in the same screen on 계속 학습, over the cards answered today, writing nothing", async () => {
      seedToday();
      await open("d1");
      const user = userEvent.setup();
      await user.keyboard("k");
      await user.keyboard("j");
      await user.keyboard("k");
      await waitFor(() => {
        expect(postgrest.rows.reviews).toHaveLength(5);
      });
      const requests = postgrest.requests.length;
      const rows = structuredClone(postgrest.rows);
      const progress = screen.getByRole("progressbar", { name: "진행" });
      const total = progress.getAttribute("aria-valuetext");

      await user.click(screen.getByRole("button", { name: "계속 학습" }));
      const practised = await answerAll("j", 3);
      await user.keyboard("z");
      await answerAll("k", 4);

      expect([...practised].sort()).toEqual(["deux", "trois", "un"]);
      expect(screen.getByRole("group", { name: "문제" })).toBeInTheDocument();
      expect(screen.getByRole("progressbar", { name: "진행" })).toBe(progress);
      expect(progress.getAttribute("aria-valuetext")).toBe(total);
      expect(stack()).toHaveLength(3 + 3 + 4);
      // Nothing reached the server: no request, and every row as it was.
      expect(postgrest.requests).toHaveLength(requests);
      expect(postgrest.rows).toEqual(rows);

      // Control: a written answer toggled now is written, behind any write practice queued, so
      // once its rating lands every earlier write has too.
      const [written] = within(
        screen.getByRole("complementary", { name: "이번 학습" }),
      ).getAllByRole("button");
      if (!written) throw new Error("no answer in the stack");
      // Later than the answer, so the server keeps the toggle as the later edit.
      vi.setSystemTime(start + 60_000);
      await user.click(written);
      const toggled = (review: Record<string, unknown>) =>
        rows.reviews.some((row) => row.id === review.id && row.rating !== review.rating);
      await waitFor(() => {
        expect(postgrest.rows.reviews.filter(toggled)).toHaveLength(1);
      });
      expect(postgrest.rows.reviews.map((row) => row.id).sort()).toEqual(
        rows.reviews.map((row) => row.id).sort(),
      );
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

    it("at rest shows exactly the previous card and the current card", async () => {
      seedDeck(postgrest, "d1", fronts);
      await open("d1");
      const [, , third] = await answerThree();

      expect(shown()).toEqual([label(third ?? "", "안다")]);
      expect(within(cards()).getAllByRole("region", { name: "현재 카드" })).toHaveLength(1);
      // Control: the list beside holds all three.
      expect(stack()).toHaveLength(3);
    });

    it("reaches earlier cards with ↑, the wheel and a downward drag, three at a time with the centred one emphasised, and returns on 지금 카드로", async () => {
      seedDeck(postgrest, "d1", fronts);
      await open("d1");
      const [first, second, third] = await answerThree();
      const user = userEvent.setup();

      await user.keyboard("{ArrowUp}");
      // The newest centred, the one before it, and the current card after it.
      expect(shown()).toEqual([label(second ?? "", "모른다"), label(third ?? "", "안다")]);
      expect(within(cards()).getByRole("region", { name: "현재 카드" })).toBeInTheDocument();

      fireEvent.wheel(cards(), { deltaY: -100 });
      expect(shown()).toEqual([
        label(first ?? "", "안다"),
        label(second ?? "", "모른다"),
        label(third ?? "", "안다"),
      ]);
      expect(within(cards()).queryByRole("region", { name: "현재 카드" })).not.toBeInTheDocument();
      const [before, centred, after] = within(cards()).getAllByRole("article");
      expect(centred?.className).toContain("scale-100");
      for (const side of [before, after]) {
        expect(side?.className).toContain("scale-90");
        expect(side?.className).toContain("opacity-70");
      }
      // The centred card alone offers the change to its other answer.
      expect(within(cards()).getAllByRole("button", { name: /로 바꾸기/ })).toHaveLength(1);

      fireEvent.touchStart(cards(), { touches: [{ clientY: 300 }] });
      fireEvent.touchEnd(cards(), { changedTouches: [{ clientY: 200 }] });
      expect(shown()).toEqual([label(second ?? "", "모른다"), label(third ?? "", "안다")]);
      fireEvent.touchStart(cards(), { touches: [{ clientY: 200 }] });
      fireEvent.touchEnd(cards(), { changedTouches: [{ clientY: 300 }] });
      expect(shown()).toHaveLength(3);

      await user.click(screen.getByRole("button", { name: "지금 카드로" }));
      expect(shown()).toEqual([label(third ?? "", "안다")]);
      expect(screen.getByRole("group", { name: "문제" })).toBeInTheDocument();
    });

    it("changes the centred card's answer with ← and →, or its button, writes the replay, and leaves the current card", async () => {
      seedDeck(postgrest, "d1", fronts);
      await open("d1");
      const [, second, third] = await answerThree();
      await waitFor(() => {
        expect(postgrest.rows.reviews).toHaveLength(3);
      });
      const current = currentFront();
      const user = userEvent.setup();
      await user.keyboard("{ArrowUp}");

      // Toward the answer it has: nothing changes.
      await user.keyboard("{ArrowRight}");
      expect(shown()[1]).toBe(label(third ?? "", "안다"));

      vi.setSystemTime(start + 60_000);
      await user.keyboard("{ArrowLeft}");
      expect(shown()[1]).toBe(`${label(third ?? "", "모른다")}. 수정됨`);
      await waitFor(() => {
        expect(postgrest.rows.reviews.filter((row) => row.rating === "again")).toHaveLength(2);
      });
      expect(postgrest.rows.reviews).toHaveLength(3);

      await user.keyboard("{ArrowUp}");
      await user.click(screen.getByRole("button", { name: "안다로 바꾸기" }));
      expect(shown()[1]).toBe(`${label(second ?? "", "안다")}. 수정됨`);

      await user.click(screen.getByRole("button", { name: "지금 카드로" }));
      expect(currentFront()).toBe(current);
      // Control: at rest, ← answers the current card.
      await user.keyboard("{ArrowLeft}");
      expect(currentFront()).not.toBe(current);
      expect(stack()).toHaveLength(4);
    });

    it("grades each previous card by its fill, its line and a chip naming the answer", async () => {
      seedDeck(postgrest, "d1", fronts);
      await open("d1");
      const [first, second] = await answerThree();
      const user = userEvent.setup();
      await user.keyboard("{ArrowUp}");
      await user.keyboard("{ArrowUp}");

      for (const [front, answer, fill, line, chip] of [
        [first, "안다", "bg-know-card", "border-know-line", "bg-know"],
        [second, "모른다", "bg-dont-know-card", "border-dont-know-line", "bg-dont-know-text"],
      ] as const) {
        const card = within(cards()).getByRole("article", { name: label(front ?? "", answer) });
        expect(card.className).toContain(fill);
        expect(card.className).toContain(line);
        const word = within(card).getByText(answer);
        expect(word.className).toContain(chip);
        expect(word.querySelector("svg")).not.toBeNull();
      }
    });

    it("shows the first-run guide on the user's first session alone, until the first answer", async () => {
      const guide = () => screen.queryByRole("region", { name: "학습 안내" });
      seedDeck(postgrest, "d1", ["un", "deux"]);
      await open("d1");

      expect(guide()).toBeInTheDocument();
      expect(within(guide() ?? document.body).getAllByRole("listitem")).toHaveLength(3);
      await userEvent.setup().keyboard("k");
      expect(guide()).not.toBeInTheDocument();

      // Control: a user with an answer stored before today sees none.
      cleanup();
      postgrest.seed("cards", cardRow("old", "d1", "old"));
      postgrest.seed("reviews", reviewRow("r-old", "old", start - 3 * day, 1_000));
      await open("d1");
      expect(screen.getByRole("group", { name: "문제" })).toBeInTheDocument();
      expect(guide()).not.toBeInTheDocument();
    });

    it("moves the cards only under prefers-reduced-motion: no-preference", async () => {
      seedDeck(postgrest, "d1", fronts);
      await open("d1");
      await answerThree();
      await userEvent.setup().keyboard("{ArrowUp}");

      const moving = [
        ...within(cards()).getAllByRole("article"),
        ...cards().querySelectorAll("[inert]"),
      ];
      expect(moving).toHaveLength(3);
      for (const element of moving) {
        const classes = element.className.split(" ");
        expect(classes.filter((name) => name.includes("transition"))).toEqual([
          "motion-safe:transition-[transform,opacity]",
        ]);
      }
    });
  });

  describe("keyboard", () => {
    beforeEach(async () => {
      seedDeck(postgrest, "d1", ["un", "deux", "trois", "quatre", "cinq"]);
      await open("d1");
    });

    it("shows the answer on Space", async () => {
      const answer = screen.getByRole("group", { name: "답" });
      expect(answer).not.toHaveTextContent(`${currentFront()} back`);

      await userEvent.setup().keyboard(" ");

      expect(answer).toHaveTextContent(`${currentFront()} back`);
      expect(screen.getByRole("button", { name: "답 보기" })).toHaveAttribute(
        "aria-pressed",
        "true",
      );
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

    it("toggles the last answer on Z", async () => {
      const user = userEvent.setup();
      await user.keyboard("k");
      await user.keyboard("j");

      await user.keyboard("z");

      expect(stack()[0]).toMatch(/답: 안다$/);
      expect(stack()[1]).toMatch(/답: 안다. 수정됨$/);
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
      for (const action of [
        "답 보기",
        "안다",
        "모른다",
        "마지막 답 바꾸기",
        "학습 끝내기",
        "단축키 보기",
      ]) {
        expect(within(help).getByText(action)).toBeInTheDocument();
      }
      await user.keyboard("{Escape}");
      expect(screen.queryByRole("dialog")).not.toBeInTheDocument();
      expect(screen.getByRole("group", { name: "문제" })).toBeInTheDocument();
    });

    it("mirrors each shortcut with a visible control", async () => {
      await userEvent.setup().keyboard("k");

      const controls = Object.fromEntries(
        ["답 보기", "안다", "모른다", "마지막 답 바꾸기", "끝내기", "단축키"].map((name) => [
          name,
          screen
            .getByRole(name === "끝내기" ? "link" : "button", { name })
            .getAttribute("aria-keyshortcuts"),
        ]),
      );

      expect(controls).toEqual({
        "답 보기": "Space",
        안다: "ArrowRight K",
        모른다: "ArrowLeft J",
        "마지막 답 바꾸기": "Z",
        끝내기: "Escape",
        단축키: "?",
      });
    });
  });
});
