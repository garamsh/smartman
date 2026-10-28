import { beforeEach, describe, expect, it, vi } from "vitest";
import { http, HttpResponse } from "msw";
import { deckRow, uuidOf } from "@/testing/library";
import { otherUser, supabaseUrl } from "@/testing/mocks/handlers";
import { FakePostgrest } from "@/testing/mocks/postgrest";
import { server } from "@/testing/mocks/server";
import { setRequestCookies } from "@/testing/next-headers";
import { signedInCookies } from "@/testing/session";
import { createDeck } from "../create-deck";
import { saveCards } from "../save-cards";
import { block, cardKey, textBlocks } from "../authoring";
import { readAllowance } from "../read-allowance";
import { parseCandidates } from "../photo-candidates";
import { parseContent } from "../card-content";

vi.mock("next/headers", () => import("@/testing/next-headers"));
vi.mock("next/cache", () => ({ revalidatePath: vi.fn() }));
let db: FakePostgrest;
beforeEach(async () => {
  db = new FakePostgrest();
  server.use(...db.handlers);
  setRequestCookies(await signedInCookies());
});
const draft = (name = " Apple ") => ({
  id: uuidOf("new-card"),
  front: textBlocks(name),
  back: [
    block("senses", {
      senses: [
        {
          labels: [{ kind: "part_of_speech", category: "noun", text: "명" }],
          meaning: "사과",
          examples: ["an apple"],
        },
      ],
    }),
  ],
});

describe("web authoring writes", () => {
  it("creates an owner-scoped private deck and a free card once across retries", async () => {
    expect(await createDeck(uuidOf("new"), "단어장")).toEqual({
      saved: true,
      deckId: uuidOf("new"),
    });
    expect(await createDeck(uuidOf("new"), "단어장")).toEqual({
      saved: true,
      deckId: uuidOf("new"),
    });
    const card = draft();
    expect(await saveCards(uuidOf("new"), [card], "manual")).toEqual({ saved: true });
    expect(await saveCards(uuidOf("new"), [card], "manual")).toEqual({ saved: true });
    expect(db.rows.decks).toHaveLength(1);
    expect(db.rows.cards).toHaveLength(1);
    expect(db.rows.cards[0]).toMatchObject({
      deck_id: uuidOf("new"),
      card_key: "apple",
      source: "manual",
      template: "free",
      template_version: 1,
    });
    expect(parseContent(db.rows.cards[0]?.back)).toEqual([
      {
        kind: "senses",
        senses: [
          {
            labels: [{ kind: "part_of_speech", category: "noun", text: "명" }],
            meaning: "사과",
            examples: ["an apple"],
          },
        ],
      },
    ]);
  });
  it("warns on the phone's normalized duplicate without overwriting it, and permits an explicit extra card", async () => {
    db.rows.decks.push(deckRow("deck", "Deck"));
    const first = draft("Ａpple");
    expect(await saveCards(uuidOf("deck"), [first], "manual")).toEqual({ saved: true });
    const second = { ...draft("apple"), id: uuidOf("second") };
    expect(await saveCards(uuidOf("deck"), [second], "manual")).toMatchObject({
      saved: false,
      duplicate: first.id,
    });
    expect(db.rows.cards).toHaveLength(1);
    expect(await saveCards(uuidOf("deck"), [second], "manual", true)).toEqual({ saved: true });
    expect(db.rows.cards).toHaveLength(2);
    expect(db.rows.cards[0]?.front).toEqual(first.front);
  });
  it("retains the request for retry after a write failure", async () => {
    db.rows.decks.push(deckRow("deck", "Deck"));
    const card = draft();
    const release = db.fail("cards", 400);
    expect(await saveCards(uuidOf("deck"), [card], "manual")).toMatchObject({ saved: false });
    expect(db.rows.cards).toHaveLength(0);
    release();
    expect(await saveCards(uuidOf("deck"), [card], "manual")).toEqual({ saved: true });
    expect(db.rows.cards).toHaveLength(1);
  });
  it("refuses invalid, foreign and deleted decks and signed-out writes beside an accepted owned deck", async () => {
    db.rows.decks.push(
      deckRow("own", "Own"),
      { ...deckRow("foreign", "Foreign", false, "public"), user_id: otherUser.id },
      deckRow("gone", "Gone", true),
    );
    const card = draft();
    for (const id of ["bad", uuidOf("foreign"), uuidOf("gone")])
      expect(await saveCards(id, [card], "manual")).toMatchObject({ saved: false });
    expect(db.rows.cards).toHaveLength(0);
    expect(await saveCards(uuidOf("own"), [card], "manual")).toEqual({ saved: true });
    setRequestCookies([]);
    expect(await createDeck(uuidOf("no-session"), "No")).toMatchObject({ saved: false });
    expect(
      await saveCards(uuidOf("own"), [{ ...card, id: uuidOf("signed-out") }], "manual"),
    ).toMatchObject({ saved: false });
    expect(db.rows.cards).toHaveLength(1);
  });
  it("refuses malformed content without changing an existing card", async () => {
    db.rows.decks.push(deckRow("own", "Own"));
    const card = draft();
    expect(await saveCards(uuidOf("own"), [card], "manual")).toEqual({ saved: true });
    expect(
      await saveCards(
        uuidOf("own"),
        [{ ...card, front: [{ type: "table", v: 2, id: "block", payload: {} }] }],
        "manual",
      ),
    ).toMatchObject({ saved: false });
    expect(db.rows.cards[0]?.front).toEqual(card.front);
  });
});

describe("photo candidates and allowance", () => {
  it("maps vocabulary senses and examples and whole cloze/table cards into existing content readers, saving only reviewed cards", async () => {
    const cards = parseCandidates({
      cards: [
        {
          kind: "vocabulary",
          type: "concept",
          front: "apple",
          topic: "과일",
          answer: "사과",
          senses: [{ labels: [], meaning: "사과", examples: ["an apple"] }],
        },
        {
          kind: "note",
          type: "cloze",
          front: "서울은 ___",
          topic: "도시",
          cloze: { answers: ["수도"] },
        },
        {
          kind: "note",
          type: "table",
          front: "도시",
          topic: "도시",
          table: {
            columns: ["도시", "나라"],
            rows: [["서울", "한국"]],
            blanks: [{ row: 0, column: 1 }],
          },
        },
      ],
    });
    expect(cards).not.toBeNull();
    expect(db.rows.cards).toHaveLength(0);
    db.rows.decks.push(deckRow("own", "Own"));
    if (!cards) throw new Error("expected candidates");
    expect(cards.map((card) => card.topic)).toEqual(["과일", "도시", "도시"]);
    expect(parseContent(cards[1]?.front)?.[0]).toMatchObject({ kind: "cloze", answers: ["수도"] });
    expect(parseContent(cards[2]?.front)?.[1]).toMatchObject({ kind: "table", spans: [] });
    expect(await saveCards(uuidOf("own"), cards.slice(0, 2), "import")).toEqual({ saved: true });
    expect(db.rows.cards).toHaveLength(2);
    expect(db.rows.cards.every((card) => card.source === "import")).toBe(true);
    expect(
      parseCandidates({
        cards: [
          {
            kind: "note",
            type: "cloze",
            front: "___ ___",
            topic: "x",
            cloze: { answers: ["one"] },
          },
        ],
      }),
    ).toBeNull();
    expect(cardKey([{ kind: "text", text: "  Ａpple\n PIE " }])).toBe("apple pie");
  });
  it("reads the current period's remaining quota and refuses malformed rows beside a valid exhausted allowance", async () => {
    server.use(
      http.post(`${supabaseUrl}/rest/v1/rpc/extraction_allowance`, () =>
        HttpResponse.json([{ photo_limit: 10, period: "month", used: 3 }]),
      ),
    );
    expect(await readAllowance()).toEqual({ remaining: 7, limit: 10, period: "month" });
    server.use(
      http.post(`${supabaseUrl}/rest/v1/rpc/extraction_allowance`, () =>
        HttpResponse.json([{ photo_limit: 10, period: "month", used: 10 }]),
      ),
    );
    expect(await readAllowance()).toEqual({ remaining: 0, limit: 10, period: "month" });
    server.use(
      http.post(`${supabaseUrl}/rest/v1/rpc/extraction_allowance`, () =>
        HttpResponse.json([{ photo_limit: 10, period: "year", used: 0 }]),
      ),
    );
    expect(await readAllowance()).toBeNull();
  });
});
