# Engine

The scheduling engine: how a card's memory state and next due time are computed from its review history.

## Current decisions

- **Location.** `engine/`, the library crate `smartman_engine`, separate from the Flutter app. The app calls it through the bridge crate in `app/rust/` ([`study.md`](study.md), [ADR 0004](adr/0004-flutter-rust-bridge.md)), which depends on it by path.
- **Algorithm.** FSRS-6 as py-fsrs v6.3.2 implements it, with its default parameters, desired retention 0.9 and a maximum interval of 36500 days ([ADR 0003](adr/0003-fsrs-engine.md)). The formulas are in `engine/src/fsrs.rs`; no FSRS crate is a dependency.
- **Pure functions.** The engine reads no clock, does no I/O and stores nothing. The caller passes the time of every review and keeps the history.
  - `review` takes a card's state (none for a new card), a rating, the time and an optional fuzz factor, and returns the new state and the due time.
  - `replay` folds a history of reviews into a state.
  - Correcting the last answer is replaying the history with that rating changed.
  - A caller may persist a state's parts instead of replaying every time; `MemoryState::from_parts` rebuilds it, and a state rebuilt from the parts of a replay equals that replay.
- **Invalid input is an error, not a panic.** The public functions return `Result` with the typed `Error`: a review dated before the last one, a number that is not a rating, and a non-finite or out-of-range stability, difficulty or fuzz factor.
- **Documented surface.** The crate denies missing docs, and `make build` builds its rustdoc with warnings denied. No bridge type lives in `engine/`.
- **Ratings.** The engine accepts the four FSRS ratings. The app's two buttons map at the public surface, not in the formulas: "Know" is `Good`, "Don't know" is `Again`.
- **No learning steps.** The state is stability, difficulty and the last review time; every interval is whole days. Re-showing a failed card within a session belongs to the app's session queue (M3).
- **Fuzz.** Given a `FuzzFactor` in `[0, 1)`, `review` fuzzes the interval as py-fsrs v6.3.2's `Scheduler._get_fuzzed_interval` does: an interval under 2.5 days is unchanged, a longer one moves to a whole number of days in a range around it that widens with the interval ([ADR 0012](adr/0012-fuzz-review-intervals.md)). The engine draws nothing: without a factor the interval is not fuzzed. Fuzz moves the due time, not the state, so `replay` takes no factor.
- **Reference values.** `engine/tests/fixtures/generate.py` runs py-fsrs 6.3.2, pinned with its dependencies in `generate.py.lock`, over fixed rating sequences and writes `engine/tests/fixtures/reference.json`: each sequence without fuzzing, and again with fuzzing under seeds 1 and 2, recording the factor each review drew. Regenerate with `uv run --locked --script engine/tests/fixtures/generate.py` from the repository root. CI does not run Python; the tests read the committed file.
- **Checks.** `make lint`, `format`, `test` and `build` each cover the crate. The toolchain is pinned in `engine/rust-toolchain.toml`; Dependabot proposes its bumps and those of `engine/Cargo.toml`.

## Rationale

- [ADR 0003](adr/0003-fsrs-engine.md) records the FSRS version and its sources, and why steps live in the session queue.
- [ADR 0012](adr/0012-fuzz-review-intervals.md) records the fuzz formula and its source, why the caller supplies the factor, and why it supersedes ADR 0003's "The engine does not fuzz".

## Open questions

- Whether desired retention or the parameters become per-user settings waits on parameter optimization from a user's review logs, which issue #5 leaves to a later milestone.
