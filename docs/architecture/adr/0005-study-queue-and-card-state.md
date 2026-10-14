# ADR 0005: Queue a session from due then new cards, re-show a "Don't know" after three cards, and store each card's state parts in `card_states`

> Status: accepted; its previous-card correction superseded by ADR-0007; its queue order, re-show gap and single-deck entry point superseded by ADR-0009
> Date: 2026-10-14

Append-only: once merged, the body below is not rewritten. A fact later found wrong is corrected in an appended note, not edited out; a revised decision is a new ADR that supersedes this one.

## Context

- Issue #12 (M3) builds the study session. The PM decided there:
  - the queue is the deck's due cards, due at or before now and earliest first, then up to 20 new cards, oldest first, with 20 a named constant;
  - a "Don't know" puts the card back a few cards later in the same session, with the gap left to this change to choose and record;
  - the previous card can be corrected from "Know" to "Don't know", recomputed from its state before that answer;
  - each card's scheduling state is stored in a table the `study` domain owns, in the shared database, as schema v2;
  - writes happen after the next card is on screen, and a failed write reaches the user.
- [ADR 0003](0003-fsrs-engine.md) keeps learning steps out of the engine, so the re-show is the session queue's. Every re-show is a review passed to the engine.
- `study.md` left two questions to M3: whether a card's state lives as its history in `reviews` or as persisted state parts, and which handler maps `EngineError` for the user.
- The engine rebuilds a state from its parts, and a state rebuilt from the parts of a replay equals that replay (`engine.md`).
- `study` depends on `deck` for its cards. The "Study" button sits on a `deck` screen, and a dependency from `deck` back to `study` would make the domain graph cyclic, which `structure.md` forbids.
- Alternatives considered for the state:
  - Replaying each card's history from `reviews` at session start. Ordering the due cards needs every reviewed card's due time, so every session start would replay every history in the deck across the bridge.
  - Keeping the state on the `cards` row. That table is `deck`'s, and `study` reaches `deck` only through its surface.
- Alternatives considered for the re-show gap:
  - The next card. The previous-card panel still shows the card's back while it is asked again.
  - The end of the queue. With 20 new cards and the due ones, the card can return dozens of cards later, or not before the user leaves.

## Decision

- **Queue.** A session's queue is built once, when it opens: every card whose stored `due` is at or before now, earliest due first and in the deck's order on a tie, then the cards with no stored state, oldest first, up to `newCardLimit` (20).
- **Re-show gap.** A "Don't know" puts the card back so that `reshowGap` (3) other cards come before it, or as many as remain. A corrected "Know" is put back the same way.
- **State storage.** Each reviewed card's stability, difficulty, last review and due time are stored in `card_states`, keyed by card id with a cascading foreign key to `cards`, owned by `study`. A card with no row is new. Schema v2 adds the table through drift's step-by-step migration.
- **Reviews.** Every answer writes one `reviews` row. A correction replaces that row's rating, keeping its id and time, and replaces the card's `card_states` row. Both writes for one answer share a transaction.
- **Order of work.** An answer changes the queue and the screen first. The engine call and the write for it then run in a chain, one answer at a time in the order given, so a re-shown card and a correction are computed from the state the earlier write produced or read.
- **Failures.** A failed write is `AnswerNotSaved`, an engine refusal `SchedulingFailure`; the session hands both to one handler, which the study screen registers to show a localized snack bar. The card's stored state then stays as it was.
- **Entry point.** `deck` declares `studyScreenProvider`, which builds the screen that studies a deck. It has no implementation of its own; the composition site overrides it with `study`'s screen, so `deck` never imports `study`.

## Consequences

- A session opens with one read of the deck's cards and one of their states, with no replay. The review history stays in `reviews`, so a later change of parameters can replay it.
- The stored state is a cache of the history. A write that fails leaves the two consistent, because both are in one transaction.
- Re-shows within a session follow the gap, not elapsed time. A card answered "Don't know" in a short queue comes back within seconds, and its review reaches the engine with the same-day stability formula.
- A failed write is reported and not retried. The session keeps the stored state as it was for that card, so a later answer to it is computed from that state.
- Changing the new-card limit or the gap means changing a named constant in `app/lib/study/src/queue.dart`; making either a user setting is a later decision.
- A second screen that starts something from a deck takes the same shape: a provider in `deck` overridden at the composition site.

## Signs the decision was wrong

- Users report seeing a "Don't know" card again too soon to have forgotten it, or too late to remember having missed it.
- Same-day re-shows drive stability down far enough that cards answered correctly the next day get intervals users find too short (the risk [ADR 0003](0003-fsrs-engine.md) names).
- `card_states` and the history in `reviews` disagree for a card, so the state has to be rebuilt by replay.
- More `deck` screens need `study` behaviour, and the providers overridden at the composition site multiply.
- Users with large backlogs find a session of every due card too long, and ask for a due-card limit.
