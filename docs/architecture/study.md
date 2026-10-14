# Study

The `study` domain: studying a deck, scheduling its cards for review, and the bridge through which it calls the Rust engine.

## Current decisions

### Surface and location

- The domain lives in `app/lib/study/`; its public surface is `app/lib/study/study.dart`, with internals under `app/lib/study/src/` ([ADR 0002](adr/0002-domain-public-surface-and-shared-database.md)).
- The surface exports what the composition site constructs and overrides: `StudyScreen`, `StudyRepository`, `Scheduler`, and the providers `studyRepositoryProvider`, `schedulerProvider` and `studyClockProvider`.
- The domain reads a deck's cards only through `deck`'s surface (`DeckRepository.listCards`, [`deck.md`](deck.md)).

### Session

- A deck's "Study" button opens `StudyScreen`. `deck` reaches it through `studyScreenProvider`, which the composition site overrides ([ADR 0005](adr/0005-study-queue-and-card-state.md)).
- The queue is built when the session opens: the cards due at or before now, earliest due first, then up to `newCardLimit` (20) cards never reviewed, oldest first. `newCardLimit` and `reshowGap` are constants in `app/lib/study/src/queue.dart`.
- A "Don't know" puts the card back so that `reshowGap` (3) other cards come before it, or as many as remain. Each re-show is a review passed to the engine.
- The screen has a top bar (the close button, a progress bar and the count of cards answered out of the session's cards), the current card, and above it every card answered so far ([ADR 0007](adr/0007-study-swipe-screen-and-session-toggle.md)). It shows no deck name, no answer button and no hint text, and never builds the next card.
- The current card:
  - sits full width less 20 on each side, its centre at 57% of the screen height while it fits;
  - holds the question on its left half and the answer on its right, hidden until a tap and hidden again by the next; when a half would be narrower than 140 at the current text scale, the answer sits under the question;
  - renders each side's content blocks through one block renderer, `ContentView`, with `UnsupportedContent` as a labelled placeholder;
  - grows with its content from 200 to 55% of the screen height, then scrolls inside.
- Dragging the current card moves and tilts it; past 40 a chip and a tint name the answer. Released past 100, or flung faster than 700 per second, it answers "Know" to the right and "Don't know" to the left, with a light haptic; otherwise it springs back.
- The previous cards are every answer of the session, re-shows included, newest nearest, in one scroll view that opens at the newest. Each shows two lines of each side, a dot for its answer and "수정됨" once the answer differs from the first given; it is smaller, greyer and blurrier a step per card of depth, and opaque. A long-press opens the whole card in a sheet.
- Tapping a previous card toggles its answer between "Know" and "Don't know", any number of times:
  - to "Don't know", a card's last answer puts the card back by `reshowGap` unless it is waiting or on screen;
  - to "Know", a card's last answer removes the card's re-show while it waits behind the card on screen;
  - any other toggle leaves the queue unchanged.
- On an answer the card flies off, the answered card rises into the stack and the next card emerges from below. Under the platform's reduce-motion setting, these become a 150 ms cross-fade.
- The session ends when the queue is empty or the user closes it, by the close button or by going back. The summary takes the current card's place: cards studied (distinct cards answered), the number of answers standing as each choice, and the time from the first card to the end.
  - After the queue empties, the stack stays, and a toggle that puts a card back reopens the session with it.
  - After closing, the stack is gone and nothing can be toggled.
- Every string comes from the shared ARB set. The current card carries a label naming its front, and its back while shown, a tap action that shows or hides the answer, and the custom actions "안다" and "모른다". Each previous card's label names its front, back and answer, with a hint that a tap changes it.
- The screen's sizes, colours and timings are constants in `app/lib/study/src/study_style.dart`; text styles come from the app theme.

### Storage

- The `reviews` and `card_states` tables in `app/lib/shared/database.dart` belong to this domain. `card_states` holds each reviewed card's stability, difficulty, last review and due time; a new card has no row. Schema v2 added it ([ADR 0005](adr/0005-study-queue-and-card-state.md)).
- Every answer writes one `reviews` row (`good` for "Know", `again` for "Don't know", with its time and duration on screen).
- Each write, after an answer or a toggle, replays the card's answers in this session as they stand, from its state when the session opened, one engine review per answer. It then rewrites those `reviews` rows, keeping their ids and times, and the card's `card_states` row, in one transaction ([ADR 0007](adr/0007-study-swipe-screen-and-session-toggle.md)).
- The engine calls and the write run after the screen has changed, chained in the order given.
- `StudyRepository` receives its id generator, and the session its clock (`studyClockProvider`), so tests fix both.

### The bridge to the engine

- The app calls the engine ([`engine.md`](engine.md)) through flutter_rust_bridge 2.13.0, built with its native-assets backend ([ADR 0004](adr/0004-flutter-rust-bridge.md)).
- The bridge crate is `rust_lib_smartman` in `app/rust/`. It depends on `engine/` by path and declares the Dart surface in `app/rust/src/api/engine.rs`:
  - `review_new_card` — a new card's first review;
  - `review_card` — a review of a card from its persisted state parts;
  - `replay` — a history folded into a state;
  - `retrievability` — the probability of recall at a time.
- Times cross the bridge as whole seconds since the Unix epoch, as the engine holds them. Answers cross as the app's two buttons, `Answer.know` and `Answer.dontKnow`.
- The generated Dart bindings are in `app/lib/study/src/rust/`; only this domain imports them.
- `Scheduler.load()` runs `RustLib.init()`, which loads the library, and returns the scheduler that calls it. The composition site awaits it before `runApp`.

### Failures

- Every engine `Error` variant arrives in Dart as one variant of the sealed `EngineError`, thrown by the call that was refused. `EngineError.unknownRating` cannot arise from this surface, which takes answers, not rating numbers.
- The bridge code itself does not panic: `app/rust/src/api/engine.rs` denies `panic!`, `unwrap`, `expect` and indexing, and `make lint` runs clippy over it. A panic inside flutter_rust_bridge's generated code reaches Dart as its `PanicException`, as an unexpected failure.
- The domain's expected failures are the sealed `StudyFailure`:
  - `SchedulingFailure` wraps an `EngineError`, thrown by `Scheduler`;
  - `AnswerNotSaved` is a failed write, and `StudyStorageFailure` a failed read, thrown by `StudyRepository`.
- A failure of a write reaches one handler, which the study screen registers with the session: a localized snack bar on the app's messenger, shown even if the screen has closed. Any other error a write raises goes to `FlutterError.reportError`, and the writes queued after it still run. A failure reading the queue is shown in place of the session; any other error there propagates.

### Build and generated code

- `flutter build` builds the crate through the hook in `app/hook/build.dart`, with the Rust release pinned in `app/rust/rust-toolchain.toml`, for every target Flutter asks for. No Android or iOS build file names the crate.
- `app/flutter_rust_bridge.yaml` configures the codegen. Its output is committed: `app/rust/src/frb_generated.rs` and `app/lib/study/src/rust/`, including the `freezed` part file of `EngineError`. `check-generated.sh` reruns the codegen, at the release `app/rust/Cargo.lock` pins, and fails when the output differs.
- To change the surface: edit `app/rust/src/api/`, run `flutter_rust_bridge_codegen generate` in `app/`, and commit what it writes.

### Tests

- `app/test/study/engine_bridge_test.dart` calls the engine through the bridge. It checks one step of `engine/tests/fixtures/reference.json`, and the arrival of a refused review as an `EngineError`.
- `app/test/study/correction_test.dart` runs a session over an in-memory database and the real engine, and checks the state stored after each toggle against a chain of the bridge's `review_card` calls over the corrected history, from the state before the session.
- `app/test/study/toggle_test.dart` covers the queue effects of a toggle; `app/test/study/queue_test.dart` covers the queue policy.
- `app/test/study/study_screen_test.dart` drives the screen on a 390 by 844 view with a scheduler that answers at once, or a repository whose writes never finish.
- `flutter test` loads the library from `app/rust/target/release/`, so `make test` builds the crate there first.

### Versions

- flutter_rust_bridge's release is pinned in `app/rust/Cargo.toml`, in `app/pubspec.yaml` for the runtime and hook packages, and, through `app/rust/Cargo.lock`, for the codegen. Dependabot proposes the cargo and pub bumps separately; one lands only with the other and with the regenerated code, or `make ci` fails.
- Dependabot also proposes the bumps of `app/rust/rust-toolchain.toml`, which stays on the release of `engine/rust-toolchain.toml`.

## Rationale

- [ADR 0004](adr/0004-flutter-rust-bridge.md) records the bridge crate's place, the native-assets backend, the location of the bindings, and each departure from flutter_rust_bridge's documented layout.
- [ADR 0005](adr/0005-study-queue-and-card-state.md) records the queue policy, the re-show gap, why the state is stored as parts in `card_states`, and how `deck` opens the session.
- [ADR 0007](adr/0007-study-swipe-screen-and-session-toggle.md) records the swipe screen, the toggleable stack, and why a toggle replays the card's session answers in Dart rather than through the bridge's `replay`.
- Issue #9 records the surface the app needs and the requirement that every engine error reach Dart typed. Issue #12 records the first session flow, and issue #18 the current screen, as decided by the PM.

## Open questions

- None.
