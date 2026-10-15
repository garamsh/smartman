# Engine

The scheduling engine: how a card's memory state and next due time are computed from its review history.

## Current decisions

- **Location.** `engine/`, the library crate `smartman_engine`, separate from the Flutter app. The app calls it through the bridge crate in `app/rust/` ([`study.md`](study.md), [ADR 0004](adr/0004-flutter-rust-bridge.md)), and the web app through the WebAssembly crate in `engine-wasm/` (below); both depend on it by path.
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

### WebAssembly

- **Crate.** `engine-wasm/`, the crate `smartman_engine_wasm`, built only for `wasm32-unknown-unknown` (`engine-wasm/.cargo/config.toml`) with the Rust release of `engine/rust-toolchain.toml` ([ADR 0018](adr/0018-engine-as-webassembly.md)). It declares its own types, converted to and from the engine's by exhaustive matches, and `engine/` holds no WASM or JS dependency.
- **Surface.** `engine-wasm/src/lib.rs` exports the bridge's operations ([`study.md`](study.md)):
  - `reviewNewCard` — a new card's first review, with an optional fuzz factor;
  - `reviewCard` — a review of a card from its persisted state parts, with an optional fuzz factor;
  - `replay` — a history folded into a state;
  - `retrievability` — the probability of recall at a time.
- **Values.** Times are whole seconds since the Unix epoch, `bigint` in TypeScript. Answers are the app's two buttons, `"know"` and `"dontKnow"`, mapped to `Good` and `Again` in the crate, as the bridge maps them.
- **Failures.** Each operation returns `Outcome<T>`, `{ ok: T }` or `{ error: EngineError }`. `EngineError` is a union told apart by `kind`, one member per engine `Error` variant; `unknownRating` cannot arise from a surface that takes answers. An argument the TypeScript types rule out, such as a `number` for a time, is thrown as a JS `Error`, as a programming error. The crate denies `panic!`, `unwrap`, `expect` and indexing.
- **Generated module.** `engine-wasm/pkg/` holds the JS glue, its `.d.ts`, with every type above declared from the Rust types by tsify, and the `.wasm`, and is committed. `./wasm-bindgen.sh generate` writes it with the `wasm-bindgen` CLI, `--target web`, at the release `engine-wasm/Cargo.lock` pins, mapping the Cargo home and the repository to fixed prefixes, with the release profile stripping symbols, so every host writes the same module. `check-generated.sh` reruns it and fails when the output differs.
- **Tests.** `make test` runs `./wasm-bindgen.sh test`: `engine-wasm/tests/` as WebAssembly in Node, through `wasm-bindgen-test-runner`.
  - `reference.rs` runs every review of every sequence in `reference.json` made only of Again and Good, unfuzzed and fuzzed, through the exported operations, and prints the count and that selection. The Hard and Easy sequences, which no answer gives, are checked by the native tests only.
  - `errors.rs` reads a refused review's returned value from JavaScript, switching on its `kind`, with an accepted control.
  - `replay.rs` reads an empty history's replay from JavaScript as `{ ok: null }`, as its declared type says.
- **Checks.** `make lint` runs clippy over the crate for `wasm32-unknown-unknown` and `make format` checks it; `make build` builds it and its rustdoc, warnings denied. Without a `wasm-bindgen` command, `check-generated.sh` and `make test` skip the crate and say so; without `node`, `make test` does. CI installs both.
- **Pins.** wasm-bindgen is pinned exactly (`=0.2.129`), as are wasm-bindgen-test and, through them, js-sys, which require it exactly; CI installs the CLI at the release in `engine-wasm/Cargo.lock`. Dependabot proposes the three as one group, and the toolchain in `engine-wasm/rust-toolchain.toml`; a wasm-bindgen bump lands with the regenerated `pkg/`. Node is pinned in `.github/workflows/ci.yml`, and the PM bumps it.

## Rationale

- [ADR 0003](adr/0003-fsrs-engine.md) records the FSRS version and its sources, and why steps live in the session queue.
- [ADR 0012](adr/0012-fuzz-review-intervals.md) records the fuzz formula and its source, why the caller supplies the factor, and why it supersedes ADR 0003's "The engine does not fuzz".
- [ADR 0018](adr/0018-engine-as-webassembly.md) records why the web app's engine is a separate crate built with the wasm-bindgen CLI, why it takes the two answers, and why errors are returned rather than thrown.

## Open questions

- Whether desired retention or the parameters become per-user settings waits on parameter optimization from a user's review logs, which issue #5 leaves to a later milestone.
