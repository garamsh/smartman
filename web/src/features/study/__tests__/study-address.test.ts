import { describe, expect, it } from "vitest";

import { studyDecks, studyHref } from "../study-address";

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
});
