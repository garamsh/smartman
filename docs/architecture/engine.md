# Engine

The scheduling engine: how a card's memory state and next due time are computed from its review history.

## Current decisions

- **Location.** `engine/`, the library crate `smartman_engine`, separate from the Flutter app; the bridge that lets the app call it is M2b and does not exist yet.
- **Algorithm.** FSRS-6 as py-fsrs v6.3.2 implements it, with its default parameters, desired retention 0.9 and a maximum interval of 36500 days ([ADR 0003](adr/0003-fsrs-engine.md)). The formulas are in `engine/src/fsrs.rs`; no FSRS crate is a dependency.
- **Pure functions.** The engine reads no clock, does no I/O and stores nothing. The caller passes the time of every review and keeps the history.
  - `review` takes a card's state (none for a new card), a rating and the time, and returns the new state and the due time.
  - `replay` folds a history of reviews into a state.
  - Correcting the last answer is replaying the history with that rating changed.
  - A caller may persist a state's parts instead of replaying every time; `MemoryState::from_parts` rebuilds it, and a state rebuilt from the parts of a replay equals that replay.
- **Invalid input is an error, not a panic.** The public functions return `Result` with the typed `Error`: a review dated before the last one, a number that is not a rating, and a non-finite or out-of-range stability or difficulty.
- **Documented surface.** The crate denies missing docs, and `make build` builds its rustdoc with warnings denied. No bridge type lives in `engine/`.
- **Ratings.** The engine accepts the four FSRS ratings. The app's two buttons map at the public surface, not in the formulas: "Know" is `Good`, "Don't know" is `Again`.
- **No learning steps, no fuzz.** The state is stability, difficulty and the last review time; every interval is whole days. Re-showing a failed card within a session belongs to the app's session queue (M3).
- **Reference values.** `engine/tests/fixtures/generate.py` runs py-fsrs 6.3.2, pinned with its dependencies in `generate.py.lock`, over fixed rating sequences and writes `engine/tests/fixtures/reference.json`. Regenerate with `uv run --locked --script engine/tests/fixtures/generate.py` from the repository root. CI does not run Python; the tests read the committed file.
- **Checks.** `make lint`, `format`, `test` and `build` each cover the crate. The toolchain is pinned in `engine/rust-toolchain.toml`; Dependabot proposes its bumps and those of `engine/Cargo.toml`.

## Rationale

- [ADR 0003](adr/0003-fsrs-engine.md) records the FSRS version and its sources, why steps live in the session queue, and why the engine does not fuzz.

## Open questions

- How the app reaches the engine — the `flutter_rust_bridge` surface and where the history is stored — is M2b's and M3's to settle.
- Whether desired retention or the parameters become per-user settings waits on parameter optimization from a user's review logs, which issue #5 leaves to a later milestone.
