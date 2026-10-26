import { describe, expect, it } from "vitest";

import { parseDeckId } from "@/features/decks";

import { studyDecks, studyHref, studyReturn } from "../study-address";

describe("the study page's address", () => {
  it("names the decks, which the page reads back in order", () => {
    const ids = ["0193a1b2-0000-7000-8000-000000000001", "0193a1b2-0000-7000-8000-000000000002"];
    const href = studyHref(ids);
    expect(href).toBe(`/study?decks=${ids.join(",")}`);
    const param = new URL(href, "http://localhost").searchParams.get("decks") ?? undefined;
    expect(studyDecks(param)).toEqual(ids);
  });

  it("reads no deck from an absent, empty or repeated parameter", () => {
    expect(studyDecks(undefined)).toEqual([]);
    expect(studyDecks("")).toEqual([]);
    expect(studyDecks(["d-1", "d-2"])).toEqual([]);
  });

  it("leaves out an id that is not a uuid, keeping the others", () => {
    const id = "0193a1b2-0000-7000-8000-000000000001";
    expect(studyDecks(`nope,${id},`)).toEqual([id]);
  });

  it("marks a session opened from a deck's page, which it returns to, and returns to 오늘 otherwise", () => {
    const id = "0193a1b2-0000-7000-8000-000000000001";
    const deck = parseDeckId(id);
    if (!deck) throw new Error("the fixed id is a uuid");
    const href = studyHref([id], "deck");
    expect(href).toBe(`/study?decks=${id}&from=deck`);
    const params = new URL(href, "http://localhost").searchParams;
    expect(studyReturn(params.get("from") ?? undefined, [deck])).toBe(`/decks/${id}`);
    // Control: the same deck opened from 오늘 returns to 오늘.
    expect(studyHref([id])).toBe(`/study?decks=${id}`);
    expect(studyReturn(undefined, [deck])).toBe("/");
  });

  it("returns to 오늘, never to an address the parameter carries, for any other from", () => {
    const deck = parseDeckId("0193a1b2-0000-7000-8000-000000000001");
    const other = parseDeckId("0193a1b2-0000-7000-8000-000000000002");
    if (!deck || !other) throw new Error("the fixed ids are uuids");
    for (const from of [
      "https://example.com",
      "//example.com/decks",
      "/account",
      "",
      ["deck", "deck"],
    ]) {
      expect(studyReturn(from, [deck])).toBe("/");
    }
    // A session over more than one deck has no one deck page to return to.
    expect(studyReturn("deck", [deck, other])).toBe("/");
    expect(studyReturn("deck", [])).toBe("/");
  });
});
