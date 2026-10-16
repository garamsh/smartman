import { describe, expect, it } from "vitest";

import type { Card, CardId, DeckId } from "@/features/decks";

import { type SessionPlan, StudySession } from "../session";

const start = Date.UTC(2026, 0, 15, 9);

const card = (front: string): Card => ({
  id: front as CardId,
  deckId: "d1" as DeckId,
  front: [{ kind: "text", text: front }],
  back: [{ kind: "text", text: `${front} back` }],
  createdAt: start,
});

/** A session over [fronts], each new, seeded at [seed]. */
function session(fronts: string[], seed = start): StudySession {
  const plan: SessionPlan = {
    startedAt: seed,
    queue: { cards: fronts.map(card), backlog: false },
    before: {},
    today: { answers: [], cards: [], answeredAnyDeck: false, streakBefore: 0 },
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

describe("practice", () => {
  it("shows every card answered today, then the missed ones until each is answered right, then every card again", () => {
    const study = session(["a", "b", "c", "d"]);
    while (study.view().kind === "studying") study.answer("know");
    expect(study.view().kind).toBe("complete");

    study.practice();
    const shown: string[] = [];
    // Misses b and d in the pass over all, and b once more in the pass over the missed.
    let missedAgain = false;
    for (let index = 0; index < 11; index++) {
      const front = current(study);
      shown.push(front);
      const inFirstPass = index < 4;
      const wrong =
        (inFirstPass && (front === "b" || front === "d")) ||
        (!inFirstPass && front === "b" && !missedAgain);
      if (!inFirstPass && front === "b") missedAgain = true;
      expect(study.answer(wrong ? "dontKnow" : "know")).toBeNull();
    }

    expect([...shown.slice(0, 4)].sort()).toEqual(["a", "b", "c", "d"]);
    expect([...shown.slice(4, 7)].sort()).toEqual(["b", "b", "d"]);
    expect([...shown.slice(7, 11)].sort()).toEqual(["a", "b", "c", "d"]);
    expect(study.view().kind).toBe("studying");
  });

  it("goes on with every card again when the pass over all misses none", () => {
    const study = session(["a", "b"]);
    study.answer("know");
    study.answer("know");
    study.practice();

    const shown = [current(study)];
    study.answer("know");
    shown.push(current(study));
    study.answer("know");
    shown.push(current(study));

    expect([...shown.slice(0, 2)].sort()).toEqual(["a", "b"]);
    expect(["a", "b"]).toContain(shown[2]);
  });

  it("returns no write for a practice answer or its toggle, and one for a written answer toggled during practice", () => {
    const study = session(["a"]);
    expect(study.answer("know")).not.toBeNull();
    study.practice();

    expect(study.answer("dontKnow")).toBeNull();
    expect(study.toggle(1)).toBeNull();
    // Control: the session's own answer still writes when toggled.
    expect(study.toggle(0)).toMatchObject({ cardId: "a", change: { kind: "toggle" } });
  });

  it("shuffles each pass from the session's source", () => {
    const orders = new Set<string>();
    for (let seed = 0; seed < 10; seed++) {
      const study = session(["a", "b", "c", "d", "e", "f"], start + seed);
      while (study.view().kind === "studying") study.answer("know");
      study.practice();
      const pass: string[] = [];
      for (let index = 0; index < 6; index++) {
        pass.push(current(study));
        study.answer("know");
      }
      expect([...pass].sort()).toEqual(["a", "b", "c", "d", "e", "f"]);
      orders.add(pass.join(""));
    }
    // Control: the passes differ between seeds.
    expect(orders.size).toBeGreaterThan(1);
  });
});
