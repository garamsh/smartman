import type { Card, CardId } from "@/features/decks";

import type { Answer, AnswerWrite, SessionReview } from "./answer-write";
import { type CardStates, orderQueue, reinsert, type SelectedQueue } from "./queue";
import { type Random, seededRandom } from "./random";

/**
 * What a study page opens with, built on the server: the cards the queue rules selected for
 * today, in the order selected, whether they are a backlog, each one's stored state, the start
 * time, which also seeds the session's random source, and what today already holds. Times are
 * milliseconds since the epoch.
 */
export type SessionPlan = {
  startedAt: number;
  queue: SelectedQueue<Card>;
  before: CardStates;
  today: {
    /** The answers stored today for the decks' cards before the session opened. */
    answers: { answer: Answer; durationMs: number }[];
    /** The cards those answers are to, each once, in the order first answered. */
    cards: Card[];
    /** Whether an answer is stored today in any deck. */
    answeredAnyDeck: boolean;
    /** Study days in a row before today holding an answer. */
    streakBefore: number;
    /** Whether an answer is stored before today in any deck. */
    answeredBefore: boolean;
  };
};

/** An answer given in this session, shown in the stack above the current card. */
export type PreviousAnswer = {
  /** Where the answer stands among the session's answers, first at 0; what `toggle` takes. */
  position: number;
  card: Card;
  answer: Answer;
  /** Whether the answer differs from the one first given. */
  changed: boolean;
};

/**
 * What the completion card shows of today's study day over the session's decks: the answers
 * stored before the session opened and the session's own written answers, as they stand.
 */
export type Completion = {
  /** Answers standing as each choice; a re-shown card counts each time. */
  knowCount: number;
  dontKnowCount: number;
  /** The time the cards were on screen before their answers. */
  timeSpentMs: number;
  /** Study days in a row with an answer, across every deck. */
  streak: number;
};

/**
 * What the screen shows: the current card, practice included; the completion card once no
 * card is left today; or nothing to study when no card is left and none was answered today.
 */
export type SessionView = {
  /** Oldest first. */
  previous: PreviousAnswer[];
  /** Cards answered at least once, of the cards in the queue when the session opened. */
  answered: number;
  total: number;
} & (
  | {
      kind: "studying";
      current: Card;
      /** Whether the user has no answer stored or given yet, so the first-run guide shows. */
      firstRun: boolean;
    }
  | { kind: "complete"; completion: Completion }
  | { kind: "empty" }
);

/**
 * An answer given in this session. A written answer holds the review that records it; a
 * practice answer holds the pass it was given in and is never written.
 */
type Answered = { card: Card; answer: Answer; first: Answer } & (
  { review: SessionReview; pass: null } | { review: null; pass: number }
);

/** Which cards a practice pass shows: every card answered today, or those missed in it. */
type Pass = "all" | "missed";

/**
 * One study session, by the queue rules of study.md. It shows the cards left today, then the
 * completion card; from there, `practice` goes on over the cards answered today, writing
 * nothing. Every random choice, the queue's order, each re-show gap, each answer's fuzz factor
 * and the practice order, comes from one source seeded with the start time. An answer or a
 * toggle changes the session at once and returns what to write, if anything.
 */
export class StudySession {
  private readonly random: Random;
  private readonly queue: Card[];
  private readonly total: number;
  private readonly answers: Answered[] = [];
  private shownAt: number;
  private practicing = false;
  private pass: Pass = "all";
  /** Counts the passes started, so a toggle can tell whether its answer is in the one under way. */
  private passNumber = 0;
  private readonly practiceQueue: Card[] = [];
  /** The cards answered "모른다" in the pass over all, oldest first. */
  private missed: Card[] = [];
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
    this.snapshot = this.build();
  }

  /** What the screen shows now; the same object until the session changes. */
  view(): SessionView {
    return this.snapshot;
  }

  /**
   * Answers the card on screen, shows the next, and returns the write that records it; a
   * practice answer is kept in the session alone, and returns none.
   */
  answer(answer: Answer): AnswerWrite | null {
    if (this.practicing) {
      this.answerPractice(answer);
      return null;
    }
    const card = this.queue[0];
    if (!card) return null;
    const now = this.clock();
    this.queue.shift();
    const review: SessionReview = {
      id: this.newId(),
      answer,
      reviewedAt: now,
      durationMs: Math.max(0, now - this.shownAt),
      fuzzFactor: this.random.nextDouble(),
    };
    this.answers.push({ card, answer, first: answer, review, pass: null });
    if (answer === "dontKnow") reinsert(this.queue, card, this.random);
    this.shownAt = now;
    this.snapshot = this.build();
    return this.write(card.id, { kind: "answer", reviewId: review.id }, now);
  }

  /**
   * Goes on from the completion card as practice: every card answered today, shuffled; then
   * the ones missed in that pass, each put back after a gap until answered right; then all
   * again, until the user stops.
   */
  practice(): void {
    if (this.snapshot.kind !== "complete") return;
    this.practicing = true;
    this.startPass("all");
    this.snapshot = this.build();
  }

  /**
   * Toggles the answer at [position] between "안다" and "모른다". A written answer returns the
   * write that reschedules its card; before practice, a toggle to "모른다" of a card's last
   * answer puts the card back as an answer would, unless it is waiting, which takes the
   * completion card away again, and a toggle to "안다" of a card's last answer removes its
   * re-show while it waits behind the card on screen. A practice answer is not written: a
   * toggle of its card's last answer in the pass under way has the same effects on the practice
   * queue, or in the pass over all adds the card to or removes it from the missed.
   */
  toggle(position: number): AnswerWrite | null {
    const answered = this.answers[position];
    if (!answered) return null;
    const { card } = answered;
    const answer: Answer = answered.answer === "know" ? "dontKnow" : "know";
    answered.answer = answer;
    if (answered.review) answered.review = { ...answered.review, answer };
    const isLast = !this.answers
      .slice(position + 1)
      .some((later) => later.card.id === card.id && later.pass === answered.pass);
    const now = this.clock();
    if (answered.pass !== null) {
      if (isLast && answered.pass === this.passNumber) this.togglePractice(card, answer);
      this.snapshot = this.build();
      return null;
    }
    if (!this.practicing && isLast) this.toggleQueued(this.queue, card, answer, now);
    this.snapshot = this.build();
    return this.write(card.id, { kind: "toggle", reviewId: answered.review.id }, now);
  }

  /**
   * Changes the answer at [position] to [answer], as `toggle` does, and returns what to write;
   * an answer that already stands as [answer] is left as it is.
   */
  redecide(position: number, answer: Answer): AnswerWrite | null {
    const answered = this.answers[position];
    if (!answered || answered.answer === answer) return null;
    return this.toggle(position);
  }

  /** Toggles the session's last answer. */
  toggleLast(): AnswerWrite | null {
    return this.toggle(this.answers.length - 1);
  }

  /** The written answers of this session, as they stand. */
  private written(): (Answered & { pass: null })[] {
    return this.answers.filter((answered): answered is Answered & { pass: null } => {
      return answered.pass === null;
    });
  }

  /** Every card answered today: before the session opened, then in it. */
  private practiceSet(): Card[] {
    const seen = new Set<CardId>();
    return [...this.plan.today.cards, ...this.written().map((answered) => answered.card)].filter(
      (card) => {
        if (seen.has(card.id)) return false;
        seen.add(card.id);
        return true;
      },
    );
  }

  private startPass(pass: Pass): void {
    const cards = pass === "all" ? this.practiceSet() : this.missed;
    this.pass = pass;
    this.passNumber += 1;
    this.missed = [];
    this.practiceQueue.push(...orderQueue({ cards, backlog: false }, this.random));
  }

  private answerPractice(answer: Answer): void {
    const card = this.practiceQueue.shift();
    if (!card) return;
    this.answers.push({ card, answer, first: answer, review: null, pass: this.passNumber });
    if (answer === "dontKnow") {
      if (this.pass === "all") this.missed.push(card);
      else reinsert(this.practiceQueue, card, this.random);
    }
    if (this.practiceQueue.length === 0) {
      this.startPass(this.pass === "all" && this.missed.length > 0 ? "missed" : "all");
    }
    this.snapshot = this.build();
  }

  private togglePractice(card: Card, answer: Answer): void {
    if (this.pass === "missed") {
      this.toggleQueued(this.practiceQueue, card, answer, this.clock());
      return;
    }
    this.missed = this.missed.filter((missed) => missed.id !== card.id);
    if (answer === "dontKnow") this.missed.push(card);
  }

  /** Puts [card] back into [queue] for a toggle to "모른다", or takes its re-show out for "안다". */
  private toggleQueued(queue: Card[], card: Card, answer: Answer, now: number): void {
    const waiting = queue.findIndex((queued) => queued.id === card.id);
    if (answer === "dontKnow" && waiting === -1) {
      if (queue.length === 0) this.shownAt = now;
      reinsert(queue, card, this.random);
    } else if (answer === "know" && waiting > 0) {
      queue.splice(waiting, 1);
    }
  }

  /** The card's written answers in this session as they stand, replayed from its state at the start. */
  private write(cardId: CardId, change: AnswerWrite["change"], editedAt: number): AnswerWrite {
    const history = this.written()
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

  private completion(): Completion {
    const written = this.written();
    const answers = [
      ...this.plan.today.answers,
      ...written.map(({ answer, review }) => ({ answer, durationMs: review.durationMs })),
    ];
    const studiedToday = this.plan.today.answeredAnyDeck || written.length > 0;
    return {
      knowCount: answers.filter(({ answer }) => answer === "know").length,
      dontKnowCount: answers.filter(({ answer }) => answer === "dontKnow").length,
      timeSpentMs: answers.reduce((sum, { durationMs }) => sum + durationMs, 0),
      streak: this.plan.today.streakBefore + (studiedToday ? 1 : 0),
    };
  }

  private build(): SessionView {
    const previous = this.answers.map((answered, position) => ({
      position,
      card: answered.card,
      answer: answered.answer,
      changed: answered.answer !== answered.first,
    }));
    const answered = new Set(this.written().map((entry) => entry.card.id)).size;
    const counts = { previous, answered, total: this.total };
    const current = this.practicing ? this.practiceQueue[0] : this.queue[0];
    if (current) {
      const { answeredAnyDeck, answeredBefore } = this.plan.today;
      const firstRun = !answeredAnyDeck && !answeredBefore && this.answers.length === 0;
      return { ...counts, kind: "studying", current, firstRun };
    }
    if (this.practiceSet().length === 0) return { ...counts, kind: "empty" };
    return { ...counts, kind: "complete", completion: this.completion() };
  }
}
