import { cleanup, screen, within } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";

import { cardRow, day, deckRow, start, stateRow } from "@/testing/library";
import { FakePostgrest } from "@/testing/mocks/postgrest";
import { server } from "@/testing/mocks/server";
import { setRequestCookies } from "@/testing/next-headers";
import { render } from "@/testing/render";
import { signedInCookies } from "@/testing/session";

import { Deck } from "../_components/deck";

vi.mock("next/headers", () => import("@/testing/next-headers"));

const open = (id: string) => render(Deck, { params: Promise.resolve({ id }) });

/** The deck's count pills, in order. */
const pills = () =>
  within(screen.getByRole("list", { name: "개수" }))
    .getAllByRole("listitem")
    .map((pill) => pill.textContent);

/** The card rows on screen, each as "front | back". */
const rows = () =>
  within(screen.getByRole("region", { name: "카드" }))
    .queryAllByRole("listitem")
    .map((row) => [...row.children].map((cell) => cell.textContent).join(" | "));

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
    expect(pills()).toEqual(["카드 3", "복습 1", "새 카드 1"]);
    expect(screen.getByRole("link", { name: "학습하기 · 2장" })).toHaveAttribute(
      "href",
      "/study?decks=d-fr",
    );
    expect(rows()).toEqual(["Chat | Chat back", "chien | chien back", "oiseau | oiseau back"]);
  });

  it("marks a deck its owner published with 공개 beside its name", async () => {
    // Control: the private deck carries no chip.
    await open("d-fr");
    expect(screen.getByRole("heading", { name: "French" })).toBeInTheDocument();
    expect(screen.queryByText("공개")).not.toBeInTheDocument();
    cleanup();

    postgrest.seed("decks", deckRow("d-pub", "Shared", false, "public"));
    await open("d-pub");
    expect(screen.getByRole("heading", { name: "Shared" })).toBeInTheDocument();
    expect(screen.getByText("공개")).toBeInTheDocument();
  });

  it("says new cards wait while more than three days of reviews are due, and not otherwise", async () => {
    const paused = "밀린 복습을 마칠 때까지 새 카드는 쉬어요.";
    // Control: one card due every four days and one every day are not a backlog.
    await open("d-fr");
    expect(pills()).toEqual(["카드 3", "복습 1", "새 카드 1"]);
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

    expect(pills()).toEqual(["카드 7", "복습 5", "새 카드 0"]);
    expect(screen.getByText(paused)).toBeInTheDocument();
    expect(screen.getByRole("link", { name: "학습하기 · 5장" })).toBeInTheDocument();
  });

  it("keeps the cards whose front or back holds the search, ignoring case", async () => {
    await open("d-fr");
    const user = userEvent.setup();

    await user.type(screen.getByRole("searchbox", { name: "검색" }), "CH");
    expect(rows()).toEqual(["Chat | Chat back", "chien | chien back"]);

    await user.clear(screen.getByRole("searchbox", { name: "검색" }));
    await user.type(screen.getByRole("searchbox", { name: "검색" }), "zèbre");
    expect(rows()).toEqual([]);
    expect(screen.getByRole("status")).toHaveTextContent(
      "찾는 카드가 없어요. 다른 말로 검색해 보세요.",
    );
  });

  it("is not found for a deleted deck, and found for a live one", async () => {
    await expect(open("d-old")).rejects.toMatchObject({ digest: "NEXT_HTTP_ERROR_FALLBACK;404" });
    await expect(open("d-fr")).resolves.toBeDefined();
  });
});
