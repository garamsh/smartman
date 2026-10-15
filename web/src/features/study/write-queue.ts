import type { CardId } from "@/features/decks";

import { type AnswerWrite, type SaveResult, writeFailureMessages } from "./answer-write";

/**
 * Where a session's writes stand: how many wait, why the first of them failed, if it did, and
 * when the first card written is due again, once every write is saved. Times are milliseconds
 * since the epoch.
 */
export type WriteStatus = { pending: number; failure: string | null; nextReview: number | null };

/**
 * Sends a session's writes to the server one at a time, in the order given, without the screen
 * waiting on any of them. A write that fails stops the queue: it and every later write wait,
 * so a toggle never reaches the server before the answer it changes, until [retry] sends them
 * again from the one that failed.
 */
export class WriteQueue {
  private readonly writes: AnswerWrite[] = [];
  private failure: string | null = null;
  private running = false;
  /** Each card's due time in the state its latest saved write stored. */
  private readonly due = new Map<CardId, number>();
  private status: WriteStatus = { pending: 0, failure: null, nextReview: null };
  private readonly listeners = new Set<() => void>();

  constructor(private readonly save: (write: AnswerWrite) => Promise<SaveResult>) {}

  /** Queues [write] behind every earlier one. */
  push(write: AnswerWrite): void {
    this.writes.push(write);
    this.changed();
    void this.run();
  }

  /** Sends the failed write and those behind it again. */
  retry(): void {
    if (this.failure === null) return;
    this.failure = null;
    this.changed();
    void this.run();
  }

  /** The current status; the same object until it changes. */
  getStatus = (): WriteStatus => this.status;

  /** Calls [listener] after each change of status; returns the function that stops it. */
  subscribe = (listener: () => void): (() => void) => {
    this.listeners.add(listener);
    return () => this.listeners.delete(listener);
  };

  private async run(): Promise<void> {
    if (this.running) return;
    this.running = true;
    while (this.failure === null) {
      const next = this.writes[0];
      if (!next) break;
      const result = await this.save(next).catch(
        // The request to this app's server failed: no connection, or the server is down.
        (): SaveResult => ({ saved: false, message: writeFailureMessages.unreachable }),
      );
      if (result.saved) {
        this.due.set(next.cardId, result.state.due);
        this.writes.shift();
        this.changed();
      } else {
        this.failure = result.message;
      }
    }
    this.running = false;
    this.changed();
  }

  private changed(): void {
    const settled = this.writes.length === 0 && this.due.size > 0;
    this.status = {
      pending: this.writes.length,
      failure: this.failure,
      nextReview: settled ? Math.min(...this.due.values()) : null,
    };
    for (const listener of this.listeners) listener();
  }
}
