import type { Card, CardId } from "@/features/decks";

import type { Answer, AnswerWrite, SessionReview } from "./answer-write";
import { type CardStates, orderQueue, reinsert, type SelectedQueue } from "./queue";
import { type Random, seededRandom } from "./random";
import { type Pace, sessionMinutes } from "./study-time";
import { todayOf } from "./today-list";

/**
 * A card of the session: `decks`' card with each side as the one line of text `decks` describes
 * it as, which the server adds, since a client module cannot import `decks`' entry point.
 */
export type StudyCard = Card & { text: { front: string; back: string } };

/**
 * What a study page opens with, built on the server: the cards left in today's list, those the
 * queue rules selected and those answered "모른다" last today, whether they are a backlog, the
 * new cards past them, the stored state of each and of each card answered today, the start time,
 * which also seeds the session's random source, the study day, the user's pace, and what today
 * already holds. Times are milliseconds since the epoch.
 */
export type SessionPlan = {
  startedAt: number;
  /** The study day the session opened in, which today's list reads. */
  day: { start: number; end: number };
  queue: SelectedQueue<StudyCard>;
  /** The new cards past today's, oldest first, which `studyOn` goes on with. */
  more: StudyCard[];
  before: CardStates;
  pace: Pace;
  today: {
    /** The answers stored today for the decks' cards before the session opened. */
    answers: { cardId: CardId; answer: Answer; reviewedAt: number; durationMs: number }[];
    /** Whether an answer is stored today in any deck. */
    answeredAnyDeck: boolean;
    /** Study days in a row before today holding an answer. */
    streakBefore: number;
  };
};

/**
 * How many cards a session opened with, and the whole minutes they take at the user's pace, as
 * the today card counts them.
 */
export type SessionSize = { cards: number; minutes: number };

/** An answer given in this session, shown in the stack above the current card. */
export type PreviousAnswer = {
  /** Where the answer stands among the session's answers, first at 0; what `toggle` takes. */
  position: number;
  card: StudyCard;
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
 * What the screen shows: the current card; the completion card once no card is left today; or
 * nothing to study when no card is left to take and none was answered today.
 */
export type SessionView = {
  /** Oldest first. */
  previous: PreviousAnswer[];
  /**
   * The day's cards whose latest answer today, in this session or an earlier one, is "안다", of
   * the day's cards: those answered today before the session opened, the queue it opened with,
   * and those taken past today's since.
   */
  answered: number;
  total: number;
} & (
  | {
      kind: "studying";
      current: StudyCard;
      /**
       * Before the session's first answer, the session's size the guide in the previous card's
       * place shows; otherwise null, and no guide shows.
       */
      guide: SessionSize | null;
    }
  | {
      kind: "complete";
      completion: Completion;
      /** Whether new cards are left past today's, which `studyOn` goes on with. */
      more: boolean;
    }
  | { kind: "empty" }
);

/** An answer given in this session and the review that records it. */
type Answered = { card: StudyCard; answer: Answer; first: Answer; review: SessionReview };

/**
 * One study session, by the queue rules of study.md. It shows the cards left today, then the
 * completion card; from there, `studyOn` goes on with the new cards past today's, oldest first,
 * each answer recorded as any other. A session that opens with no card left today starts on
 * those at once. Every random choice, the queue's order, each re-show gap and each answer's
 * fuzz factor, comes from one source seeded with the start time. An answer or a toggle changes
 * the session at once and returns what to write, if anything.
 */
export class StudySession {
  private readonly random: Random;
  private readonly queue: StudyCard[];
  /** The day's cards, each once: answered today before the session, queued, or taken since. */
  private readonly dayCards: Set<CardId>;
  /** The new cards past today's, oldest first, not yet taken. */
  private more: StudyCard[];
  /** The session's size when it opened. */
  private readonly size: SessionSize;
  private readonly answers: Answered[] = [];
  private shownAt: number;
  /** When the page was last hidden while the card on screen waited, or null while it is visible. */
  private pausedAt: number | null = null;
  /** The time hidden since the card on screen was shown, up to `pausedAt`. */
  private awayMs = 0;
  private snapshot: SessionView;

  constructor(
    private readonly plan: SessionPlan,
    private readonly clock: () => number,
    private readonly newId: () => string,
  ) {
    this.random = seededRandom(plan.startedAt);
    this.queue = orderQueue(plan.queue, this.random);
    this.dayCards = new Set([
      ...plan.today.answers.map((answer) => answer.cardId),
      ...this.queue.map((card) => card.id),
    ]);
    const fresh = this.queue.filter((card) => !plan.before[card.id]).length;
    this.size = {
      cards: this.queue.length,
      minutes: sessionMinutes(this.queue.length - fresh, fresh, plan.pace),
    };
    this.more = [...plan.more];
    // Opening the page with no card left today is the choice to go on.
    if (this.queue.length === 0) this.takeMore();
    this.shownAt = plan.startedAt;
    this.snapshot = this.build();
  }

  /** What the screen shows now; the same object until the session changes. */
  view(): SessionView {
    return this.snapshot;
  }

  /** Answers the card on screen, shows the next, and returns the write that records it. */
  answer(answer: Answer): AnswerWrite | null {
    const card = this.queue[0];
    if (!card) return null;
    const now = this.clock();
    this.queue.shift();
    const review: SessionReview = {
      id: this.newId(),
      answer,
      reviewedAt: now,
      durationMs: this.onScreen(now),
      fuzzFactor: this.random.nextDouble(),
    };
    this.answers.push({ card, answer, first: answer, review });
    if (answer === "dontKnow") reinsert(this.queue, card, this.random);
    this.show(now);
    this.snapshot = this.build();
    return this.write(card.id, { kind: "answer", reviewId: review.id }, now);
  }

  /**
   * Stops the clock of the card on screen while the page is hidden, so an answer's duration
   * counts only the time the page was visible.
   */
  pause(): void {
    this.pausedAt ??= this.clock();
  }

  /** Starts the clock of the card on screen again as the page is shown. */
  resume(): void {
    if (this.pausedAt !== null) this.awayMs += this.clock() - this.pausedAt;
    this.pausedAt = null;
  }

  /** Starts the clock of the next card shown, at [now]. */
  private show(now: number): void {
    this.shownAt = now;
    this.awayMs = 0;
    if (this.pausedAt !== null) this.pausedAt = now;
  }

  /** The time the card on screen has been shown at [now] with the page visible. */
  private onScreen(now: number): number {
    const away = this.awayMs + (this.pausedAt === null ? 0 : now - this.pausedAt);
    return Math.max(0, now - this.shownAt - away);
  }

  /**
   * Goes on from the completion card with the new cards past today's, oldest first; with none
   * left, does nothing.
   */
  studyOn(): void {
    if (this.snapshot.kind !== "complete" || this.more.length === 0) return;
    this.takeMore();
    this.show(this.clock());
    this.snapshot = this.build();
  }

  /** Moves the new cards past today's into the queue. */
  private takeMore(): void {
    this.queue.push(...this.more);
    for (const card of this.more) this.dayCards.add(card.id);
    this.more = [];
  }

  /**
   * Toggles the answer at [position] between "안다" and "모른다" and returns the write that
   * reschedules its card. A toggle to "모른다" of a card's last answer puts the card back as an
   * answer would, unless it is waiting, which takes the completion card away again, and a toggle
   * to "안다" of a card's last answer removes its re-show while it waits behind the card on
   * screen.
   */
  toggle(position: number): AnswerWrite | null {
    const answered = this.answers[position];
    if (!answered) return null;
    const { card } = answered;
    const answer: Answer = answered.answer === "know" ? "dontKnow" : "know";
    answered.answer = answer;
    answered.review = { ...answered.review, answer };
    const isLast = !this.answers.slice(position + 1).some((later) => later.card.id === card.id);
    const now = this.clock();
    if (isLast) this.toggleQueued(card, answer, now);
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

  /** Puts [card] back into the queue for a toggle to "모른다", or takes its re-show out for "안다". */
  private toggleQueued(card: StudyCard, answer: Answer, now: number): void {
    const waiting = this.queue.findIndex((queued) => queued.id === card.id);
    if (answer === "dontKnow" && waiting === -1) {
      if (this.queue.length === 0) this.show(now);
      reinsert(this.queue, card, this.random);
    } else if (answer === "know" && waiting > 0) {
      this.queue.splice(waiting, 1);
    }
  }

  /** The card's written answers in this session as they stand, replayed from its state at the start. */
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

  private completion(): Completion {
    const written = this.answers;
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
    const places = todayOf(
      this.dayCards,
      this.plan.before,
      [
        ...this.plan.today.answers,
        ...this.answers.map(({ card, review }) => ({
          cardId: card.id,
          answer: review.answer,
          reviewedAt: review.reviewedAt,
        })),
      ],
      this.plan.day,
    );
    const answered = [...places.values()].filter((place) => place === "done").length;
    const counts = { previous, answered, total: this.dayCards.size };
    const current = this.queue[0];
    if (current) {
      const guide = this.answers.length === 0 ? this.size : null;
      return { ...counts, kind: "studying", current, guide };
    }
    if (this.plan.today.answers.length === 0 && this.answers.length === 0) {
      return { ...counts, kind: "empty" };
    }
    return {
      ...counts,
      kind: "complete",
      completion: this.completion(),
      more: this.more.length > 0,
    };
  }
}
