# ADR 0007: Answer by swiping a split card, keep every session answer in a toggleable stack, and reschedule a toggle by replaying the card's session answers

> Status: accepted
> Date: 2026-10-15

Append-only: once merged, the body below is not rewritten. A fact later found wrong is corrected in an appended note, not edited out; a revised decision is a new ADR that supersedes this one.

## Context

- Issue #18 replaces the study screen with a design the owner approved on 2026-10-14. The PM decided there:
  - the current card is split, question left and answer right, the answer shown on tap; a swipe right is "Know" and a swipe left "Don't know", with no answer buttons and no hint text;
  - every card answered in the session stays above the current card in one scroll view, opaque and receding with depth, and a tap toggles its answer either way, any number of times, while the screen is open;
  - a toggle recomputes the card by replaying its reviews in this session, at their original times, from its state before the session; the affected `reviews` rows and its `card_states` row are rewritten in one transaction;
  - the queue effects of a toggle, the reopening of an emptied session, and that the summary counts the current answers;
  - reduce motion turns every transition into a short cross-fade.
- [ADR 0005](0005-study-queue-and-card-state.md) allowed one correction, of the previous card, from "Know" to "Don't know" only, recomputed from the state before that answer. Its queue policy, re-show gap, state storage and entry point are not in question.
- The bridge's `replay` (`app/rust/src/api/engine.rs`) folds a history from a new card; it takes no starting state. A due card's state before the session is the stored `card_states` row, not a history the session holds.
- Four points the issue leaves open were settled by the PM in the dispatch of issue #18:
  - the close button and the system back end the session as back did: the summary shows without the stack, and nothing can be toggled after;
  - a re-show already on screen has been shown, so a toggle to "Know" does not remove it;
  - once the queue is empty, the summary takes the current card's place under the stack, with a Done button, and the stack stays toggleable;
  - the replay folds one `review_card` call per review in Dart, with no change to the bridge.
- Alternatives considered for the recompute:
  - Adding a starting state to the bridge's `replay`. The issue rules out a bridge change while the existing surface can express the recompute, and folding `review_card` does.
  - Replaying the card's whole history from `reviews`. The stored state already caches every review before the session ([ADR 0005](0005-study-queue-and-card-state.md)), so only the session's reviews need folding.
  - Recomputing only the toggled answer and the ones after it. That needs each answer's state before it kept beside the session, which the replay makes unnecessary.

## Decision

- **Screen.** A top bar with the close button, a progress bar and the count of cards answered out of the session's cards. Below it, the current card, its centre at 57% of the screen height while it fits, and above it the stack of previous cards. The next card is never built.
- **Current card.** Its question and answer render each side's content blocks through one block renderer, side by side, or the answer under the question when a half would be narrower than 140 logical pixels at the current text scale. The card grows with its content from 200 to 55% of the screen height and then scrolls inside.
- **Answering.** A horizontal drag moves and tilts the card; past 40 a chip and tint name the answer; a release past 100, or a fling faster than 700 per second, commits it, with a light haptic, and anything else springs back. Screen readers get the custom actions "안다" and "모른다" and a tap that shows or hides the answer.
- **Stack.** Every answer of the session, re-shows included, oldest at the top, in one lazily built scroll view that opens at the newest. Each card shows two lines of each side and a status dot, steps down in scale, greys and blurs with depth up to a cap past which it is not blurred, and stays opaque. A tap toggles the answer, and a long-press opens the whole card in a sheet.
- **Toggle and queue.** A toggle flips the answer at its position. A toggle to "Don't know" of a card's last answer puts the card back by `reshowGap` unless it is already waiting or on screen; after the queue has emptied this reopens the session. A toggle to "Know" of a card's last answer removes the card's re-show while it waits behind the card on screen. Any other toggle leaves the queue as it is.
- **Rescheduling.** Every write, an answer's or a toggle's, folds the card's answers in this session, as they stand, from its state when the session opened, one engine review per answer, and writes all of those `reviews` rows and its `card_states` row in one transaction. No other card's rows are written.
- **Motion.** On commit the card flies off for 200 ms, the answered card rises into the stack and the next card emerges from below and smaller over 300 ms. Under reduce motion the card does not fly, the stack does not move, and the cards cross-fade in 150 ms.
- **Style.** The screen's sizes, colours and timings are named constants in `app/lib/study/src/study_style.dart`; text styles come from the app theme.

## Consequences

- An answer can be corrected wherever it stands in the session, not only the last one, and a card answered several times is rescheduled from all of them.
- A write for a card with *k* answers in the session makes *k* engine calls and writes *k* review rows. Sessions are short, so *k* stays small.
- A write that failed is repaired by the card's next write in the session, which rewrites every one of its session reviews. ADR 0005's "a later answer is computed from the stored state" no longer holds within a session.
- Once the user leaves, the stack is gone and nothing can be toggled, so the summary reached by leaving cannot reopen the session.
- The bridge surface is unchanged; `replay` stays for a history that starts from a new card.
- A new content block type adds a block widget and a span to the block renderer; the card layout does not change.

## Signs the decision was wrong

- Users toggle a card to "Don't know" and expect it back, but it was on screen or already waiting, so nothing visible happens.
- Long sessions make the per-write replay slow enough that a toggle's state lags behind the next answer of the same card.
- The width rule stacks cards that would have fit side by side, or leaves halves too narrow to read, at text scales users actually set.
- Users swipe by accident while scrolling the stack, or cannot find how to answer without a hint.
- The depth blur or grey makes previous cards hard to read, and users ask for them sharp.
