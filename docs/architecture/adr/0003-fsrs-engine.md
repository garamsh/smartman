# ADR 0003: Schedule with FSRS-6 as py-fsrs 6.3.2 implements it, in a pure engine without learning steps

> Status: accepted; its "The engine does not fuzz" superseded by ADR-0012; its learning and relearning left to the session queue alone superseded by ADR-0061, which keeps a card failed today in today's list through an engine function
> Date: 2026-10-14

Append-only: once merged, the body below is not rewritten. A fact later found wrong is corrected in an appended note, not edited out; a revised decision is a new ADR that supersedes this one.

## Context

- The PM decided in issue #5 that the scheduling engine is our own Rust crate, `engine/`, written from the published FSRS description rather than taken from an FSRS crate, and that a reference implementation only supplies expected values for tests.
- Issue #5 fixes the FSRS version as the one the current `open-spaced-repetition/py-fsrs` release implements, with desired retention 0.9.
- That release is py-fsrs v6.3.2 (PyPI `fsrs` 6.3.2, uploaded 2026-08-09; tag `v6.3.2` at commit `9446cb06605c597a063aeee49f7d188d42e34dc2`). Its `fsrs/scheduler.py` implements FSRS-6: 21 parameters, `w[20]` the trainable forgetting-curve decay.
- The formula page is <https://github.com/open-spaced-repetition/awesome-fsrs/wiki/The-Algorithm>, read at wiki commit `7bcf7dc343fc81d0fc55db2705c8b8fe85c2daa5`; the page it replaced, <https://github.com/open-spaced-repetition/fsrs4anki/wiki/The-Algorithm>, now only links there. Its section "FSRS-6" states the changes from FSRS-5, which states its changes from FSRS-4.5 and FSRS v4.
- The wiki does not state four things py-fsrs v6.3.2 does: post-lapse stability is capped at `S / e^(w17 · w18)`; stability is clamped to at least 0.001 and difficulty to `[1, 10]`; mean reversion targets the unclamped `D0(4)`; the interval is rounded half to even (Python `round`), kept within 1 to 36500 days. Expected values only match with these, so the engine takes them from that source.
- py-fsrs v6.3.2 default parameters: `0.212, 1.2931, 2.3065, 8.2956, 6.4133, 0.8334, 3.0194, 0.001, 1.8722, 0.1666, 0.796, 1.4835, 0.0614, 0.2629, 1.6483, 0.6014, 1.8729, 0.5425, 0.0912, 0.0658, 0.1542`. The wiki's section "FSRS-6" lists the same.
- py-fsrs adds two things on top of the memory model. Learning and relearning steps (defaults 1 and 10 minutes, and 10 minutes) re-show a new or failed card within minutes through a Learning/Relearning state machine. Fuzzing randomises intervals longer than two days.
- The app has two buttons and an M3 session queue that already decides what to show next within a session. The engine is pure: no clock, no I/O, no stored state.

## Decision

- The engine implements FSRS-6 as py-fsrs v6.3.2 does, including the four points the wiki omits, with its default parameters, desired retention 0.9 and maximum interval 36500 days.
- Learning and relearning steps live in the app's session queue (M3), not in the engine. The engine computes every review with the memory model alone, as py-fsrs does with `learning_steps=()` and `relearning_steps=()`, so every interval is whole days and a review less than a day after the previous one takes the same-day stability formula.
- The engine does not fuzz. Its results are those of py-fsrs with `enable_fuzzing=False`.

## Consequences

- The engine's state is stability, difficulty and the time of the last review, with no Learning/Relearning state and no step counter; a history replays to the same state wherever it runs.
- Re-showing a failed card within a session, and how soon, is the session queue's to decide. Each re-show the app records is passed to the engine like any other review.
- A "Don't know" schedules the card no sooner than one day out; the same session is not the engine's concern.
- Due dates are not spread by fuzz, so cards learned together stay due together.
- Reference values come from py-fsrs v6.3.2 configured as above. Moving to a newer FSRS version means regenerating them and recording the new version.

## Signs the decision was wrong

- The session queue grows its own Learning/Relearning state machine that duplicates py-fsrs's, or it needs the engine's state to decide what to re-show.
- Same-day re-shows recorded as reviews drive stability down so far that cards answered correctly the next day get intervals users report as too short.
- Cards studied together pile up due on the same day often enough that users report it.
- A later py-fsrs release changes one of the four points the wiki omits, and the engine has to follow a reference rather than a description.
