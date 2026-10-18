import { beforeAll, describe, expect, it } from "vitest";

import type { CardId, DeckId } from "@/features/decks";

import { loadEngine } from "../engine";
import { type SessionPlan, type StudyCard, StudySession } from "../session";
import { unknownPace } from "../study-time";

const start = Date.UTC(2026, 0, 15, 9);

const card = (front: string): StudyCard => ({
  id: front as CardId,
  deckId: "d1" as DeckId,
  front: [{ kind: "text", text: front }],
  back: [{ kind: "text", text: `${front} back` }],
  createdAt: start,
  text: { front, back: `${front} back` },
});

/**
 * A session over today's new cards [today] and the new cards past them [more], with [stored]
 * answers given today before it opened.
 */
function session(today: string[], more: string[], stored = 0): StudySession {
  const plan: SessionPlan = {
    startedAt: start,
    day: { start: start - 43_200_000, end: start + 43_200_000 },
    queue: { cards: today.map(card), backlog: false },
    more: more.map(card),
    before: {},
    pace: unknownPace,
    today: {
      answers: Array.from({ length: stored }, (_, index) => ({
        cardId: `stored${String(index)}` as CardId,
        answer: "know" as const,
        reviewedAt: start - 1000,
        durationMs: 0,
      })),
      answeredAnyDeck: stored > 0,
      streakBefore: 0,
    },
  };
  let id = 0;
  return new StudySession(
    plan,
    () => start,
    () => `review${String((id += 1))}`,
  );
}

/** The front of the card on screen. */
function current(study: StudySession): string {
  const view = study.view();
  if (view.kind !== "studying") throw new Error(`no card is on screen: ${view.kind}`);
  return view.current.id;
}

beforeAll(loadEngine);

describe("studying past today's cards", () => {
  it("goes on from the completion card with the new cards past today's, oldest first, each answer written and counted", () => {
    const study = session(["a", "b"], ["c", "d"]);
    study.answer("know");
    study.answer("know");
    const complete = study.view();
    expect(complete).toMatchObject({ kind: "complete", more: true, answered: 2, total: 2 });

    study.studyOn();
    expect(current(study)).toBe("c");
    expect(study.answer("know")?.cardId).toBe("c");
    expect(current(study)).toBe("d");
    expect(study.answer("know")?.cardId).toBe("d");
    expect(study.view()).toMatchObject({ kind: "complete", more: false, answered: 4, total: 4 });
  });

  it("shows a card answered past today's again only as the re-show after 모른다", () => {
    const study = session(["a"], ["b", "c"]);
    study.answer("know");
    study.studyOn();
    const shown: string[] = [];
    for (const answer of ["dontKnow", "know", "know"] as const) {
      shown.push(current(study));
      study.answer(answer);
    }
    expect(shown).toEqual(["b", "c", "b"]);
    expect(study.view()).toMatchObject({ kind: "complete", more: false });
  });

  it("opens straight on the new cards past today's when none is left today, under a guide whose size holds no card", () => {
    // Control: a session with a card left today opens on it, its guide sized.
    const withToday = session(["a"], ["b"]).view();
    expect(withToday).toMatchObject({ kind: "studying", guide: { cards: 1 } });

    const study = session([], ["b", "c"], 1);
    expect(study.view()).toMatchObject({
      kind: "studying",
      guide: { cards: 0 },
      // The day's count goes on from the card answered "안다" today.
      answered: 1,
      total: 3,
    });
    expect(current(study)).toBe("b");
    study.answer("know");
    expect(study.view()).toMatchObject({ kind: "studying", guide: null });
  });

  it("with no card left to take opens on the completion card when today holds an answer, and on nothing to study otherwise", () => {
    const answered = session([], [], 1);
    expect(answered.view()).toMatchObject({ kind: "complete", more: false });
    answered.studyOn();
    expect(answered.view()).toMatchObject({ kind: "complete", more: false });

    expect(session([], []).view().kind).toBe("empty");
  });
});
