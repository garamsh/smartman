import { cleanup, screen, waitFor, within } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { afterEach, beforeAll, beforeEach, describe, expect, it, vi } from "vitest";
import { loadEngine } from "@/features/study";

import { cardRow, day, deckRow, reviewRow, side, start, stateRow, uuidOf } from "@/testing/library";
import { FakePostgrest } from "@/testing/mocks/postgrest";
import { supabaseUnreachable } from "@/testing/mocks/handlers";
import { server } from "@/testing/mocks/server";
import { setRequestCookies } from "@/testing/next-headers";
import { render } from "@/testing/render";
import { signedInCookies } from "@/testing/session";
import { sensesUnder } from "@/testing/senses";
import { blanksUnder } from "@/testing/whole-cards";

import { Deck } from "../_components/deck";
import { Study } from "../../../../study/_components/study";

// The study screen starts its session once the browser's engine has loaded; its first load
// compiles the module.
beforeAll(async () => {
  await loadEngine();
}, 30_000);

vi.mock("next/headers", () => import("@/testing/next-headers"));

/** Opens the page of the deck named [name]. */
const open = (name: string) => render(Deck, { params: Promise.resolve({ id: uuidOf(name) }) });

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
    .queryAllByRole("button", { name: /, 뒷면 / })
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
      `/study?decks=${uuidOf("d-fr")}&from=deck`,
    );
    expect(screen.getByRole("link", { name: "학습하기" })).toHaveAttribute(
      "aria-keyshortcuts",
      "Enter",
    );
    // Every answer hidden until it is asked for.
    expect(rows()).toEqual(["Chat, 뒷면 가려짐", "chien, 뒷면 가려짐", "oiseau, 뒷면 가려짐"]);
    // Two learning and one new: the progress, read as one sentence.
    const bar = screen.getByRole("img", { name: "익힘 0장, 학습 중 2장, 새 카드 1장" });
    // On the navy card: learning in white at 45%, as the phone draws it, with no gap between shares.
    const learning = Array.from(bar.querySelectorAll<HTMLElement>("span[style]")).find((span) =>
      span.style.width.startsWith("66.6"),
    );
    expect(learning?.className.split(" ")).toEqual(["bg-on-hero/45"]);
    expect(bar.className.split(" ")).not.toEqual(
      expect.arrayContaining([expect.stringMatching(/^gap-/)]),
    );
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
      expect(href, answered).toBe(`/study?decks=${uuidOf("d-done")}&from=deck`);

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
      // Every 그만하기, the close and the completion card's, returns to this deck's page.
      const ways = screen.getAllByRole("link", { name: "그만하기" });
      expect(ways.length, answered).toBe(answered === "yesterday" ? 1 : 2);
      for (const way of ways) {
        expect(way, answered).toHaveAttribute("href", `/decks/${uuidOf("d-done")}`);
      }
      cleanup();
    }
  });

  it("offers no 학습하기 on a deck with no card, which has nothing to study", async () => {
    // Control: the deck with cards links it.
    await open("d-fr");
    expect(screen.getByRole("link", { name: "학습하기" })).toBeInTheDocument();
    cleanup();

    postgrest.seed("decks", deckRow("d-empty", "Empty"));
    await open("d-empty");
    expect(screen.getByRole("heading", { name: "Empty" })).toBeInTheDocument();
    expect(screen.queryByRole("link", { name: "학습하기" })).not.toBeInTheDocument();
  });

  it("shows an empty deck as the first run does, with the phone's words and where cards are added", async () => {
    postgrest.seed("decks", deckRow("d-empty", "Empty"));
    await open("d-empty");

    const empty = screen.getByRole("region", { name: "아직 카드가 없어요" });
    expect(empty).toHaveTextContent(
      "카드는 휴대폰 앱에서 덱에 추가해요. 추가한 카드는 여기에도 보여요.",
    );
    expect(screen.queryByRole("searchbox", { name: "카드 검색" })).not.toBeInTheDocument();
    // Control: a deck with cards lists them instead.
    cleanup();
    await open("d-fr");
    expect(screen.queryByRole("region", { name: "아직 카드가 없어요" })).not.toBeInTheDocument();
  });

  it("keeps the way back to 덱 and a heading above a failed read, with 다시 시도", async () => {
    server.use(supabaseUnreachable);
    await open("d-fr");

    expect(
      within(screen.getByRole("navigation", { name: "위치" })).getByRole("link", { name: "덱" }),
    ).toHaveAttribute("href", "/decks");
    const heading = screen.getByRole("heading", { level: 1, name: "덱을 불러오지 못했어요" });
    const alert = screen.getByRole("alert");
    expect(heading.compareDocumentPosition(alert) & Node.DOCUMENT_POSITION_FOLLOWING).toBeTruthy();
    expect(alert).toHaveTextContent("서버에 연결할 수 없어요.");
    expect(within(alert).getByRole("button", { name: "다시 시도" })).toBeInTheDocument();
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
    expect(rows()).toEqual(["Chat, 뒷면 가려짐", "chien, 뒷면 가려짐"]);
    // The results follow the switch.
    await user.click(screen.getByRole("switch", { name: "뜻 보기" }));
    expect(rows()).toEqual(["Chat, 뒷면 Chat back", "chien, 뒷면 chien back"]);
    expect(screen.getByRole("heading", { name: "카드 2" })).toBeInTheDocument();

    await user.clear(screen.getByRole("searchbox", { name: "카드 검색" }));
    await user.type(screen.getByRole("searchbox", { name: "카드 검색" }), "zèbre");
    expect(rows()).toEqual([]);
    expect(screen.getByRole("status")).toHaveTextContent(
      "찾는 카드가 없어요. 다른 단어로 검색해 보세요.",
    );
  });

  it("shows a card's back on a click and hides it on the next, that card alone", async () => {
    await open("d-fr");
    const user = userEvent.setup();

    await user.click(screen.getByRole("button", { name: "chien, 뒷면 가려짐" }));
    expect(rows()).toEqual(["Chat, 뒷면 가려짐", "chien, 뒷면 chien back", "oiseau, 뒷면 가려짐"]);
    expect(screen.getByRole("button", { name: "chien, 뒷면 chien back" })).toHaveAttribute(
      "aria-expanded",
      "true",
    );
    await user.click(screen.getByRole("button", { name: "chien, 뒷면 chien back" }));
    expect(rows()).toEqual(["Chat, 뒷면 가려짐", "chien, 뒷면 가려짐", "oiseau, 뒷면 가려짐"]);
  });

  it("shows a vocabulary card's senses on a click, each label in brackets with a gap after it, a part of speech by its short form", async () => {
    postgrest.seed("cards", {
      ...cardRow("c-train", "d-fr", "train", day / 2),
      back: [
        {
          type: "senses",
          payload: {
            senses: [
              {
                labels: [
                  { kind: "part_of_speech", category: "noun", text: "n." },
                  { kind: "other", category: null, text: "사물" },
                ],
                meaning: "기차",
                examples: [],
              },
              { labels: [], meaning: "열차", examples: [] },
            ],
          },
        },
      ],
    });
    await open("d-fr");

    await userEvent.setup().click(screen.getByRole("button", { name: "train, 뒷면 가려짐" }));
    const card = screen.getByRole("button", { name: "train, 뒷면 [명] [사물] 기차\n열차" });
    expect(sensesUnder(card)).toEqual([
      { labels: ["[명]", "[사물]"], gapped: true, text: "[명][사물]기차" },
      { labels: [], gapped: true, text: "열차" },
    ]);
  });

  it("shows a whole card's front with its blank empty in place of the bar over the back, and fills it on a click", async () => {
    postgrest.seed("cards", {
      ...cardRow("c-cloze", "d-fr", "cloze", day / 2),
      front: [
        { type: "cloze", payload: { text: "The capital of France is ___", answers: ["Paris"] } },
      ],
      back: side("The capital of France is Paris"),
    });
    await open("d-fr");
    const user = userEvent.setup();

    const hidden = screen.getByRole("button", {
      name: "The capital of France is 빈칸, 뒷면 가려짐",
    });
    expect(blanksUnder(hidden)).toEqual({ Paris: false });
    await user.click(hidden);
    const filledCard = screen.getByRole("button", {
      name: "The capital of France is 빈칸, 뒷면 The capital of France is Paris",
    });
    expect(blanksUnder(filledCard)).toEqual({ Paris: true });
    // Control: the split cards keep their answers hidden.
    expect(rows()).toContain("Chat, 뒷면 가려짐");
  });

  it("shows or hides every back with 뜻 보기, off when the page opens, resetting a card set apart by a click", async () => {
    await open("d-fr");
    const user = userEvent.setup();
    const answers = screen.getByRole("switch", { name: "뜻 보기" });
    expect(answers).toHaveAttribute("aria-checked", "false");
    expect(screen.getByRole("heading", { name: "카드 3" })).toBeInTheDocument();

    await user.click(answers);
    expect(answers).toHaveAttribute("aria-checked", "true");
    expect(rows()).toEqual([
      "Chat, 뒷면 Chat back",
      "chien, 뒷면 chien back",
      "oiseau, 뒷면 oiseau back",
    ]);
    // A click after the switch sets that card alone apart.
    await user.click(screen.getByRole("button", { name: "Chat, 뒷면 Chat back" }));
    expect(rows()).toEqual([
      "Chat, 뒷면 가려짐",
      "chien, 뒷면 chien back",
      "oiseau, 뒷면 oiseau back",
    ]);
    // The switch then sets every card to its state, the one set apart included.
    await user.click(answers);
    expect(rows()).toEqual(["Chat, 뒷면 가려짐", "chien, 뒷면 가려짐", "oiseau, 뒷면 가려짐"]);
    await user.click(answers);
    expect(rows()).toEqual([
      "Chat, 뒷면 Chat back",
      "chien, 뒷면 chien back",
      "oiseau, 뒷면 oiseau back",
    ]);
  });

  it("leads back to 덱 with a chevron, on a target at least the tap target high and wide", async () => {
    await open("d-fr");

    const back = within(screen.getByRole("navigation", { name: "위치" })).getByRole("link", {
      name: "덱",
    });
    expect(back).toHaveAttribute("href", "/decks");
    expect(back.querySelector("svg")).toHaveAttribute("aria-hidden", "true");
    expect(back.className.split(" ")).toEqual(
      expect.arrayContaining(["min-h-tap-target", "min-w-tap-target"]),
    );
  });

  it("is not found for a deleted deck, and found for a live one", async () => {
    await expect(open("d-old")).rejects.toMatchObject({ digest: "NEXT_HTTP_ERROR_FALLBACK;404" });
    await expect(open("d-fr")).resolves.toBeDefined();
  });

  it("is not found for an address id that is not a uuid, and found for the deck's own id", async () => {
    await expect(render(Deck, { params: Promise.resolve({ id: "d-fr" }) })).rejects.toMatchObject({
      digest: "NEXT_HTTP_ERROR_FALLBACK;404",
    });
    // Control: the same deck by its uuid opens.
    await open("d-fr");
    expect(screen.getByRole("heading", { name: "French" })).toBeInTheDocument();
  });
});
