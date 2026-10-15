import { screen, within } from "@testing-library/react";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";

import { FakePostgrest } from "@/testing/mocks/postgrest";
import { server } from "@/testing/mocks/server";
import { cardRow, day, deckRow, start, stateRow } from "@/testing/library";
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
    expect(screen.getByText("복습 1 · 새 카드 1")).toBeInTheDocument();
    expect(screen.getByRole("link", { name: "모두 학습" })).toHaveAttribute(
      "href",
      "/study?decks=d-fr,d-es",
    );
    expect(screen.getByRole("heading", { name: "내 덱 2" })).toBeInTheDocument();
    expect(rowNames()).toEqual(["French, 카드 3장, 오늘 2", "Spanish, 카드 1장"]);
    expect(row("French")).toHaveAttribute("href", "/decks/d-fr");
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
    const other = "00000000-0000-4000-8000-000000000002";
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

  it("says the server cannot be reached when PostgREST does not answer", async () => {
    postgrest.fail("decks", 500);

    await render(Decks, {});

    expect(screen.getByRole("alert")).toHaveTextContent(
      "서버에 연결할 수 없어요. 연결을 확인하고 다시 시도해 주세요.",
    );
  });

  it("shows how to start when there is no deck", async () => {
    await render(Decks, {});

    expect(
      screen.getByText("아직 덱이 없습니다. 휴대폰 앱에서 덱을 만들면 여기에 나타나요."),
    ).toBeInTheDocument();
    expect(screen.getByRole("button", { name: "모두 학습" })).toBeDisabled();
  });
});
