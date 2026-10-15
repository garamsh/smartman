import type { Card, CardId } from "@/features/decks";

import type { Answer, AnswerWrite, SessionReview } from "./answer-write";
import { type CardStates, orderQueue, reinsert, type SelectedQueue } from "./queue";
import { type Random, seededRandom } from "./random";

/**
 * What a study page opens with, built on the server: the cards the queue rules selected, in
 * the order selected, whether they are a backlog, each one's stored state, and the start time,
 * which also seeds the session's random source. Times are milliseconds since the epoch.
 */
export type SessionPlan = { startedAt: number; queue: SelectedQueue<Card>; before: CardStates };

/** An answer given in this session, shown in the stack above the current card. */
export type PreviousAnswer = {
  /** Where the answer stands among the session's answers, first at 0; what `toggle` takes. */
  position: number;
  card: Card;
  answer: Answer;
  /** Whether the answer differs from the one first given. */
  changed: boolean;
};

/** The counts a finished session shows, from the answers as they stand. */
export type SessionSummary = {
  /** Distinct cards answered at least once. */
  cardsStudied: number;
  /** Answers standing as each choice; a re-shown card counts each time. */
  knowCount: number;
  dontKnowCount: number;
  timeSpentMs: number;
};

/** What the screen shows: the current card, or the summary once the session is over. */
export type SessionView = {
  /** Oldest first; empty once the user has left. */
  previous: PreviousAnswer[];
  /** Cards answered at least once, of the cards in the queue when the session opened. */
  answered: number;
  total: number;
} & ({ kind: "studying"; current: Card } | { kind: "finished"; summary: SessionSummary });

type Answered = { card: Card; review: SessionReview; first: Answer };

/**
 * One study session, by the queue rules of study.md. Every random choice, the queue's order,
 * each re-show gap and each answer's fuzz factor, comes from one source seeded with the start
 * time. An answer or a toggle changes the session at once and returns what to write.
 */
export class StudySession {
  private readonly random: Random;
  private readonly queue: Card[];
  private readonly total: number;
  private readonly answers: Answered[] = [];
  private shownAt: number;
  private endedAt: number | null = null;
  private left = false;
  private snapshot: SessionView;

  constructor(
    private readonly plan: SessionPlan,
    private readonly clock: () => number,
    private readonly newId: () => string,
  ) {
    this.random = seededRandom(plan.startedAt);
    this.queue = orderQueue(plan.queue, this.random);
    this.total = this.queue.length;
    this.shownAt = plan.startedAt;
    if (this.queue.length === 0) this.endedAt = plan.startedAt;
    this.snapshot = this.build();
  }

  /** What the screen shows now; the same object until the session changes. */
  view(): SessionView {
    return this.snapshot;
  }

  /** Answers the card on screen, shows the next, and returns the write that records it. */
  answer(answer: Answer): AnswerWrite | null {
    const card = this.queue[0];
    if (!card || this.endedAt !== null) return null;
    const now = this.clock();
    this.queue.shift();
    const review: SessionReview = {
      id: this.newId(),
      answer,
      reviewedAt: now,
      durationMs: Math.max(0, now - this.shownAt),
      fuzzFactor: this.random.nextDouble(),
    };
    this.answers.push({ card, review, first: answer });
    if (answer === "dontKnow") reinsert(this.queue, card, this.random);
    this.shownAt = now;
    if (this.queue.length === 0) this.endedAt = now;
    this.snapshot = this.build();
    return this.write(card.id, { kind: "answer", reviewId: review.id }, now);
  }

  /**
   * Toggles the answer at [position] between "안다" and "모른다", and returns the write that
   * reschedules its card. A toggle to "모른다" of a card's last answer puts the card back as an
   * answer would, unless it is waiting; after the queue has emptied this reopens the session.
   * A toggle to "안다" of a card's last answer removes its re-show while it waits behind the
   * card on screen.
   */
  toggle(position: number): AnswerWrite | null {
    const answered = this.answers[position];
    if (!answered || this.left) return null;
    const { card } = answered;
    const answer: Answer = answered.review.answer === "know" ? "dontKnow" : "know";
    answered.review = { ...answered.review, answer };
    const isLast = !this.answers.slice(position + 1).some((later) => later.card.id === card.id);
    const waiting = this.queue.findIndex((queued) => queued.id === card.id);
    const now = this.clock();
    if (isLast && answer === "dontKnow" && waiting === -1) {
      if (this.queue.length === 0) {
        this.endedAt = null;
        this.shownAt = now;
      }
      reinsert(this.queue, card, this.random);
    } else if (isLast && answer === "know" && waiting > 0) {
      this.queue.splice(waiting, 1);
    }
    this.snapshot = this.build();
    return this.write(card.id, { kind: "toggle", reviewId: answered.review.id }, now);
  }

  /** Toggles the session's last answer. */
  toggleLast(): AnswerWrite | null {
    return this.toggle(this.answers.length - 1);
  }

  /** Ends the session early: the summary shows, and nothing can be toggled. */
  leave(): void {
    if (this.endedAt !== null) return;
    this.endedAt = this.clock();
    this.left = true;
    this.snapshot = this.build();
  }

  /** The card's answers in this session as they stand, replayed from its state at the start. */
  private write(cardId: CardId, change: AnswerWrite["change"], editedAt: number): AnswerWrite {
    const history = this.answers
      .filter((answered) => answered.card.id === cardId)
      .map((answered) => answered.review);
    const [first, ...rest] = history;
    if (!first) throw new Error(`no answer in this session for ${cardId}`);
    return {
      cardId,
      before: this.plan.before[cardId] ?? null,
      history: [first, ...rest],
      change,
      editedAt,
    };
  }

  private build(): SessionView {
    const previous = this.left
      ? []
      : this.answers.map((answered, position) => ({
          position,
          card: answered.card,
          answer: answered.review.answer,
          changed: answered.review.answer !== answered.first,
        }));
    const answered = new Set(this.answers.map((entry) => entry.card.id)).size;
    const counts = { previous, answered, total: this.total };
    const current = this.queue[0];
    if (this.endedAt === null && current) return { ...counts, kind: "studying", current };
    const standing = this.answers.map((entry) => entry.review.answer);
    return {
      ...counts,
      kind: "finished",
      summary: {
        cardsStudied: answered,
        knowCount: standing.filter((answer) => answer === "know").length,
        dontKnowCount: standing.filter((answer) => answer === "dontKnow").length,
        timeSpentMs: (this.endedAt ?? this.clock()) - this.plan.startedAt,
      },
    };
  }
}
