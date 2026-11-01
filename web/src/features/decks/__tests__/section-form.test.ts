import { describe, expect, it } from "vitest";
import { formFor, sectionsOf } from "../section-form";
import type { Candidate } from "../photo-candidates";

/** A candidate of [kind] under [topic], an identify card when [identify]. */
function candidate(topic: string, kind: Candidate["kind"], identify = false): Candidate {
  return {
    id: `${topic}-${kind}-${String(identify)}`,
    reverseId: "reverse",
    topic,
    kind,
    identify,
    pronunciation: null,
    extras: [],
    front: [],
    back: [],
    selected: !identify,
  };
}

describe("section forms", () => {
  it("groups a photo's cards by topic, kind and identify, in the order each first appears, under the phone's keys", () => {
    const sections = sectionsOf("photo", [
      candidate("과일", "vocabulary"),
      candidate("도시", "note"),
      candidate("도시", "note", true),
      candidate("과일", "vocabulary"),
      candidate("과일", "note"),
    ]);
    expect(sections.map(({ id, key, cards }) => [id, key, cards.length])).toEqual([
      ["photo|vocabulary:과일", "vocabulary:과일", 2],
      ["photo|note:도시", "note:도시", 1],
      ["photo|identify:note:도시", "identify:note:도시", 1],
      ["photo|note:과일", "note:과일", 1],
    ]);
  });
  it("takes a stored form of the section's own kind as the phone stores it, and refuses another kind's or a malformed one", () => {
    const [vocabulary, note] = sectionsOf("photo", [
      candidate("과일", "vocabulary"),
      candidate("도시", "note"),
    ]);
    if (!vocabulary || !note) throw new Error("two sections");
    const stored = {
      direction: "both",
      firstSenseOnly: true,
      showPos: false,
      showPronunciation: true,
      showExtras: false,
    };
    expect(formFor(vocabulary, stored)).toEqual({ kind: "vocabulary", ...stored });
    expect(formFor(note, { swapped: true })).toEqual({ kind: "note", swapped: true });
    expect(formFor(note, stored)).toBeNull();
    expect(formFor(vocabulary, { swapped: true })).toBeNull();
    expect(formFor(vocabulary, { ...stored, direction: "sideways" })).toBeNull();
    expect(formFor(vocabulary, { ...stored, showExtras: "yes" })).toBeNull();
    expect(formFor(note, null)).toBeNull();
  });
});
