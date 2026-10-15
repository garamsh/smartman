import { act, cleanup, screen, waitFor, within } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";

import { cardRow, day, seedDeck, start, stateRow } from "@/testing/library";
import { FakePostgrest } from "@/testing/mocks/postgrest";
import { server } from "@/testing/mocks/server";
import { setRequestCookies } from "@/testing/next-headers";
import { render } from "@/testing/render";
import { signedInCookies } from "@/testing/session";

import { Study } from "../_components/study";

vi.mock("next/headers", () => import("@/testing/next-headers"));

/** Opens the study page over [decks] at [at], as the browser would with `?decks=`. */
async function open(decks: string, at = start) {
  vi.setSystemTime(at);
  await render(Study, { searchParams: Promise.resolve({ decks }) });
}

/** The front of the card on screen. */
const currentFront = () => screen.getByRole("group", { name: "문제" }).textContent;

/** The accessible names of the answers in the stack, oldest first. */
const stack = () =>
  within(screen.getByRole("region", { name: "이전 답" }))
    .getAllByRole("button")
    .map((button) => button.getAttribute("aria-label"));

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
      expect(screen.getByRole("heading", { name: "오늘 할 카드를 마쳤어요" })).toBeInTheDocument();
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

    it("names the next review in the summary once every answer is saved", async () => {
      seedDeck(postgrest, "d1", ["un", "deux"]);
      await open("d1");
      const user = userEvent.setup();
      await user.keyboard("k");
      await waitFor(() => {
        expect(postgrest.rows.card_states).toHaveLength(1);
      });
      const release = postgrest.hold("reviews");

      await user.keyboard("k");

      // Control: the summary is up while the second write waits, without the next review.
      expect(screen.getByRole("heading", { name: "오늘 할 카드를 마쳤어요" })).toBeInTheDocument();
      expect(screen.queryByText(/^다음 복습은/)).not.toBeInTheDocument();
      act(release);
      await waitFor(() => {
        expect(postgrest.rows.card_states).toHaveLength(2);
      });
      // The earliest stored due day, counted in calendar days from today in this time zone.
      const midnight = (time: number) => {
        const date = new Date(time);
        return new Date(date.getFullYear(), date.getMonth(), date.getDate()).getTime();
      };
      const due = Math.min(...postgrest.rows.card_states.map((row) => Date.parse(String(row.due))));
      const days = Math.round((midnight(due) - midnight(start)) / day);
      // A new card answered 안다 is next due days later, as the engine schedules it.
      expect(days).toBeGreaterThan(1);
      expect(
        await screen.findByText(
          `다음 복습은 ${String(days)}일 뒤예요. 잊을 때쯤 다시 보여 드릴게요.`,
        ),
      ).toBeInTheDocument();
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

  describe("keyboard", () => {
    beforeEach(async () => {
      seedDeck(postgrest, "d1", ["un", "deux", "trois", "quatre", "cinq"]);
      await open("d1");
    });

    it("shows the answer on Space", async () => {
      const answer = screen.getByRole("group", { name: "답" });
      expect(answer).toHaveTextContent("답이 가려져 있어요.");

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

    it("ends the session on Esc", async () => {
      const user = userEvent.setup();
      await user.keyboard("k");

      await user.keyboard("{Escape}");

      expect(screen.getByRole("heading", { name: "오늘 할 카드를 마쳤어요" })).toBeInTheDocument();
      expect(
        within(screen.getByRole("list", { name: "결과" }))
          .getAllByRole("listitem")
          .map((tile) => tile.textContent),
      ).toEqual(["1학습한 카드", "1안다", "0모른다"]);
      expect(screen.queryByRole("region", { name: "이전 답" })).not.toBeInTheDocument();
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
          screen.getByRole("button", { name }).getAttribute("aria-keyshortcuts"),
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
