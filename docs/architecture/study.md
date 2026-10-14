# Study

The `study` domain: scheduling cards for review, and the bridge through which it calls the Rust engine.

## Current decisions

### Surface and location

- The domain lives in `app/lib/study/`; its public surface is `app/lib/study/study.dart`, with internals under `app/lib/study/src/` ([ADR 0002](adr/0002-domain-public-surface-and-shared-database.md)).
- The surface exports nothing yet. The study session (M3) decides what it exports.
- The `reviews` table in `app/lib/shared/database.dart` belongs to this domain; nothing writes it yet ([`deck.md`](deck.md)).

### The bridge to the engine

- The app calls the engine ([`engine.md`](engine.md)) through flutter_rust_bridge 2.13.0, built with its native-assets backend ([ADR 0004](adr/0004-flutter-rust-bridge.md)).
- The bridge crate is `rust_lib_smartman` in `app/rust/`. It depends on `engine/` by path and declares the Dart surface in `app/rust/src/api/engine.rs`:
  - `review_new_card` — a new card's first review;
  - `review_card` — a review of a card from its persisted state parts;
  - `replay` — a history folded into a state;
  - `retrievability` — the probability of recall at a time.
- Times cross the bridge as whole seconds since the Unix epoch, as the engine holds them. Answers cross as the app's two buttons, `Answer.know` and `Answer.dontKnow`.
- The generated Dart bindings are in `app/lib/study/src/rust/`; only this domain imports them.
- `RustLib.init()` loads the library and must complete before the first call. Nothing calls it yet; the composition site does so when M3 first uses the engine.

### Failures

- Every engine `Error` variant arrives in Dart as one variant of the sealed `EngineError`, thrown by the call that was refused. `EngineError.unknownRating` cannot arise from this surface, which takes answers, not rating numbers.
- The bridge code itself does not panic: `app/rust/src/api/engine.rs` denies `panic!`, `unwrap`, `expect` and indexing, and `make lint` runs clippy over it. A panic inside flutter_rust_bridge's generated code reaches Dart as its `PanicException`, as an unexpected failure.

### Build and generated code

- `flutter build` builds the crate through the hook in `app/hook/build.dart`, with the Rust release pinned in `app/rust/rust-toolchain.toml`, for every target Flutter asks for. No Android or iOS build file names the crate.
- `app/flutter_rust_bridge.yaml` configures the codegen. Its output is committed: `app/rust/src/frb_generated.rs` and `app/lib/study/src/rust/`, including the `freezed` part file of `EngineError`. `check-generated.sh` reruns the codegen, at the release `app/rust/Cargo.lock` pins, and fails when the output differs.
- To change the surface: edit `app/rust/src/api/`, run `flutter_rust_bridge_codegen generate` in `app/`, and commit what it writes.

### Tests

- `app/test/study/engine_bridge_test.dart` calls the engine through the bridge. It checks one step of `engine/tests/fixtures/reference.json`, and the arrival of a refused review as an `EngineError`.
- `flutter test` loads the library from `app/rust/target/release/`, so `make test` builds the crate there first.

### Versions

- flutter_rust_bridge's release is pinned in `app/rust/Cargo.toml`, in `app/pubspec.yaml` for the runtime and hook packages, and, through `app/rust/Cargo.lock`, for the codegen. Dependabot proposes the cargo and pub bumps separately; one lands only with the other and with the regenerated code, or `make ci` fails.
- Dependabot also proposes the bumps of `app/rust/rust-toolchain.toml`, which stays on the release of `engine/rust-toolchain.toml`.

## Rationale

- [ADR 0004](adr/0004-flutter-rust-bridge.md) records the bridge crate's place, the native-assets backend, the location of the bindings, and each departure from flutter_rust_bridge's documented layout.
- Issue #9 records the surface the app needs and the requirement that every engine error reach Dart typed.

## Open questions

- Where a card's state lives between reviews, as its history in `reviews` or as persisted state parts, is M3's to settle.
- Which handler maps `EngineError` for the user is M3's to settle with the session screen.
