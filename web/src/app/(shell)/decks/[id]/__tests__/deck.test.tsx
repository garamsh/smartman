import { cleanup, screen, waitFor, within } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { afterEach, beforeAll, beforeEach, describe, expect, it, vi } from "vitest";
import { loadEngine } from "@/features/study";

import { cardRow, day, deckRow, reviewRow, start, stateRow } from "@/testing/library";
import { FakePostgrest } from "@/testing/mocks/postgrest";
import { server } from "@/testing/mocks/server";
import { setRequestCookies } from "@/testing/next-headers";
import { render } from "@/testing/render";
import { signedInCookies } from "@/testing/session";

import { Deck } from "../_components/deck";
import { Study } from "../../../../study/_components/study";

// The study screen starts its session once the browser's engine has loaded; its first load
// compiles the module.
beforeAll(async () => {
  await loadEngine();
}, 30_000);

vi.mock("next/headers", () => import("@/testing/next-headers"));

const open = (id: string) => render(Deck, { params: Promise.resolve({ id }) });

/** What the page says of the deck: its card count under the name, and today's cards for it. */
const summary = () => ({
  cards: /카드 (\d+)장/.exec(screen.getByRole("banner").textContent)?.[1],
  today: /오늘 할 카드 (\d+)장/.exec(
    within(screen.getByRole("region", { name: "오늘 이 덱" }))
      .getByLabelText(/^오늘 할 카드/)
      .getAttribute("aria-label") ?? "",
  )?.[1],
});

/** The cards on screen, each as its button names it: its front, and its answer or that it is hidden. */
const rows = () =>
  within(screen.getByRole("region", { name: "카드" }))
    .queryAllByRole("button", { name: /, 답 / })
    .map((card) => card.getAttribute("aria-label"));

describe("the deck page", () => {
  let postgrest: FakePostgrest;
  beforeEach(async () => {
    vi.useFakeTimers({ toFake: ["Date"] });
    vi.setSystemTime(start);
    setRequestCookies(await signedInCookies());
    postgrest = new FakePostgrest();
    server.use(...postgrest.handlers);
    postgrest.seed("decks", deckRow("d-fr", "French"), deckRow("d-old", "Old", true));
    postgrest.seed(
      "cards",
      cardRow("c-chat", "d-fr", "Chat", 3 * day),
      cardRow("c-chien", "d-fr", "chien", 2 * day),
      cardRow("c-later", "d-fr", "oiseau", day),
      cardRow("c-gone", "d-fr", "maison", day, true),
    );
    postgrest.seed(
      "card_states",
      stateRow("c-chien", { stability: 3, difficulty: 5, lastReview: start - 4 * day, due: start }),
      stateRow("c-later", { stability: 9, difficulty: 5, lastReview: start, due: start + day }),
    );
  });
  afterEach(() => {
    vi.useRealTimers();
  });

  it("shows the name, today's line, the study button and the live cards, oldest first", async () => {
    await open("d-fr");

    expect(screen.getByRole("heading", { name: "French" })).toBeInTheDocument();
    expect(summary()).toEqual({ cards: "3", today: "2" });
    expect(screen.getByRole("link", { name: "학습하기" })).toHaveAttribute(
      "href",
      "/study?decks=d-fr",
    );
    expect(screen.getByRole("link", { name: "학습하기" })).toHaveAttribute(
      "aria-keyshortcuts",
      "Enter",
    );
    // Every answer hidden until it is asked for.
    expect(rows()).toEqual(["Chat, 답 가려짐", "chien, 답 가려짐", "oiseau, 답 가려짐"]);
    // Two learning and one new: the progress, read as one sentence.
    expect(
      screen.getByRole("img", { name: "익힘 0장, 학습 중 2장, 새 카드 1장" }),
    ).toBeInTheDocument();
    expect(screen.getByRole("link", { name: "덱" })).toHaveAttribute("href", "/decks");
  });

  it("with no card left today still links 학습하기 · 0장 to the study page, which opens on nothing to study or on the completion card", async () => {
    postgrest.seed("decks", deckRow("d-done", "Done"));
    postgrest.seed("cards", cardRow("c-done", "d-done", "fini"));
    postgrest.seed(
      "card_states",
      stateRow("c-done", {
        stability: 9,
        difficulty: 5,
        lastReview: start - day,
        due: start + day,
      }),
    );
    // Answered yesterday: nothing was answered today.
    postgrest.seed("reviews", reviewRow("r-yesterday", "c-done", start - day, 1_000));

    for (const answered of ["yesterday", "today"]) {
      if (answered === "today") {
        postgrest.seed("reviews", reviewRow("r-today", "c-done", start - 3_600_000, 1_000));
      }
      await open("d-done");

      expect(summary(), answered).toEqual({ cards: "1", today: "0" });
      const href = screen.getByRole("link", { name: "학습하기" }).getAttribute("href");
      expect(href, answered).toBe("/study?decks=d-done");

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

  it("marks a deck its owner published with 공개 under its name", async () => {
    // Control: the private deck carries no chip.
    await open("d-fr");
    expect(screen.getByRole("heading", { name: "French" })).toBeInTheDocument();
    expect(screen.getByText("카드 3장")).toBeInTheDocument();
    cleanup();

    postgrest.seed("decks", deckRow("d-pub", "Shared", false, "public"));
    await open("d-pub");
    expect(screen.getByRole("heading", { name: "Shared" })).toBeInTheDocument();
    expect(screen.getByText("카드 0장 · 공개")).toBeInTheDocument();
  });

  it("says new cards wait while more than three days of reviews are due, and not otherwise", async () => {
    const paused = "밀린 복습을 마칠 때까지 새 카드는 쉬어요.";
    // Control: one card due every four days and one every day are not a backlog.
    await open("d-fr");
    expect(summary()).toEqual({ cards: "3", today: "2" });
    expect(screen.queryByText(paused)).not.toBeInTheDocument();
    cleanup();

    // Four more due after 30 days: five due against a load of about 1.4 a day.
    const overdue = ["un", "deux", "trois", "quatre"];
    postgrest.seed("cards", ...overdue.map((front) => cardRow(`c-${front}`, "d-fr", front)));
    postgrest.seed(
      "card_states",
      ...overdue.map((front) =>
        stateRow(`c-${front}`, {
          stability: 30,
          difficulty: 5,
          lastReview: start - 31 * day,
          due: start - day,
        }),
      ),
    );
    await open("d-fr");

    expect(summary()).toEqual({ cards: "7", today: "5" });
    expect(screen.getByText(paused)).toBeInTheDocument();
    expect(screen.getByRole("link", { name: "학습하기" })).toBeInTheDocument();
  });

  it("keeps the cards whose front or back holds the search, ignoring case", async () => {
    await open("d-fr");
    const user = userEvent.setup();

    await user.type(screen.getByRole("searchbox", { name: "카드 검색" }), "CH");
    expect(rows()).toEqual(["Chat, 답 가려짐", "chien, 답 가려짐"]);
    // The results follow the switch.
    await user.click(screen.getByRole("switch", { name: "뜻 보기" }));
    expect(rows()).toEqual(["Chat, 답 Chat back", "chien, 답 chien back"]);
    expect(screen.getByRole("heading", { name: "카드 2" })).toBeInTheDocument();

    await user.clear(screen.getByRole("searchbox", { name: "카드 검색" }));
    await user.type(screen.getByRole("searchbox", { name: "카드 검색" }), "zèbre");
    expect(rows()).toEqual([]);
    expect(screen.getByRole("status")).toHaveTextContent(
      "찾는 카드가 없어요. 다른 말로 검색해 보세요.",
    );
  });

  it("shows a card's answer on a click and hides it on the next, that card alone", async () => {
    await open("d-fr");
    const user = userEvent.setup();

    await user.click(screen.getByRole("button", { name: "chien, 답 가려짐" }));
    expect(rows()).toEqual(["Chat, 답 가려짐", "chien, 답 chien back", "oiseau, 답 가려짐"]);
    expect(screen.getByRole("button", { name: "chien, 답 chien back" })).toHaveAttribute(
      "aria-expanded",
      "true",
    );
    await user.click(screen.getByRole("button", { name: "chien, 답 chien back" }));
    expect(rows()).toEqual(["Chat, 답 가려짐", "chien, 답 가려짐", "oiseau, 답 가려짐"]);
  });

  it("shows or hides every answer with 뜻 보기, off when the page opens, resetting a card set apart by a click", async () => {
    await open("d-fr");
    const user = userEvent.setup();
    const answers = screen.getByRole("switch", { name: "뜻 보기" });
    expect(answers).toHaveAttribute("aria-checked", "false");
    expect(screen.getByRole("heading", { name: "카드 3" })).toBeInTheDocument();

    await user.click(answers);
    expect(answers).toHaveAttribute("aria-checked", "true");
    expect(rows()).toEqual([
      "Chat, 답 Chat back",
      "chien, 답 chien back",
      "oiseau, 답 oiseau back",
    ]);
    // A click after the switch sets that card alone apart.
    await user.click(screen.getByRole("button", { name: "Chat, 답 Chat back" }));
    expect(rows()).toEqual(["Chat, 답 가려짐", "chien, 답 chien back", "oiseau, 답 oiseau back"]);
    // The switch then sets every card to its state, the one set apart included.
    await user.click(answers);
    expect(rows()).toEqual(["Chat, 답 가려짐", "chien, 답 가려짐", "oiseau, 답 가려짐"]);
    await user.click(answers);
    expect(rows()).toEqual([
      "Chat, 답 Chat back",
      "chien, 답 chien back",
      "oiseau, 답 oiseau back",
    ]);
  });

  it("is not found for a deleted deck, and found for a live one", async () => {
    await expect(open("d-old")).rejects.toMatchObject({ digest: "NEXT_HTTP_ERROR_FALLBACK;404" });
    await expect(open("d-fr")).resolves.toBeDefined();
  });
});
