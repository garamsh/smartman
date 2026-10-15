import { screen, within } from "@testing-library/react";
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
    expect(
      within(screen.getByRole("list", { name: "개수" }))
        .getAllByRole("listitem")
        .map((pill) => pill.textContent),
    ).toEqual(["카드 3", "복습 1", "새 카드 1"]);
    expect(screen.getByRole("link", { name: "학습하기 · 2장" })).toHaveAttribute(
      "href",
      "/study?decks=d-fr",
    );
    expect(rows()).toEqual(["Chat | Chat back", "chien | chien back", "oiseau | oiseau back"]);
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
