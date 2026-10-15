# Study

The `study` domain: studying one or more decks, scheduling their cards for review, and the bridge through which it calls the Rust engine.

## Current decisions

### Surface and location

- The domain lives in `app/lib/study/`; its public surface is `app/lib/study/study.dart`, with internals under `app/lib/study/src/` ([ADR 0002](adr/0002-domain-public-surface-and-shared-database.md)).
- The surface exports what the composition site constructs and overrides: `StudyScreen`, `TodayCounter`, `StudyRepository`, `Scheduler`, and the providers `studyRepositoryProvider`, `schedulerProvider`, `studyClockProvider` and `studyRandomProvider`.
- `Scheduler.fold` is the fold `sync` recomputes a card's state with: the card's stored reviews in `reviewed_at` order, through the engine from a new card, each with its stored fuzz factor and a null factor as none ([`sync.md`](sync.md)). The domain does not import `sync`.
- The domain reads the decks' cards only through `deck`'s surface (`DeckRepository.listCards`, [`deck.md`](deck.md)).

### Session

- A session studies a `DeckSelection`: one deck from its card list, the selected decks from the deck list's selection mode, or every deck from the header card. `deck` reaches `StudyScreen` through `studyScreenProvider` and `TodayCounter` through `todayProvider`, both overridden by the composition site ([ADR 0005](adr/0005-study-queue-and-card-state.md), [ADR 0009](adr/0009-multi-deck-session-and-random-queue-order.md), [ADR 0011](adr/0011-shared-app-theme-bundled-font-and-today-builder.md)).
- The queue is built when the session opens, from the cards of every selected deck ([ADR 0025](adr/0025-order-a-review-backlog-by-due-date-and-pause-new-cards.md)):
  - the daily load is the sum, over every reviewed card of the decks, of one over its interval in days (due time less last review), at least one;
  - the decks are in backlog when the cards due at or before now outnumber `backlogDays` (3) times the daily load;
  - in backlog, the queue is every due card, earliest due first, equal due times in the order read, and no new card; each run of `backlogBucketSize` (10) consecutive cards is shuffled in its place;
  - otherwise, the queue is every due card and up to `newCardLimit` (20) cards never reviewed across the decks, oldest first by creation time, shuffled together, so each new card lands at a random place among the due ones ([ADR 0009](adr/0009-multi-deck-session-and-random-queue-order.md)).
- Each shuffle is a forward Fisher–Yates over its run, the whole queue out of backlog, a draw of 0 keeping the card in its place.
- A "Don't know" puts the card back after a gap drawn from `reshowGapMin` (3) to `reshowGapMax` (5) other cards, or after as many as remain. Each re-show is a review passed to the engine.
- `newCardLimit`, `reshowGapMin`, `reshowGapMax`, `backlogDays` and `backlogBucketSize` are constants in `app/lib/study/src/queue.dart`. The web app applies the same rules, with the same constants, in `web/src/features/study/queue.ts` ([`web.md`](web.md)); a change to them changes both.
- Every random choice of a session comes from one `Random`, which `studyRandomProvider` makes from the session's start time. The composition site seeds it from that time; tests inject their own.
- `TodayCounter` counts the queue a session over its decks would build now, as due cards and new ones, or as due cards in a backlog, and passes the count to the builder `deck` gives it: the deck list's today card, a deck row's chip, the card list's pills and study button. In a backlog the today card and the card list add "밀린 복습을 마칠 때까지 새 카드는 쉬어요." ([`deck.md`](deck.md)). It reads the count when it is built, when its decks change, and when its route comes back on top; a failed read is passed on as its localized message.
- The count carries the time one card takes the user: the median `duration_ms` of their latest 200 reviews that are not deleted, or 10 s while they have fewer than 20, which the today card turns into minutes ([ADR 0027](adr/0027-draw-both-clients-in-the-smartman-brand-and-the-v2-screens.md)).
- The screen has a top bar (the close button, an 8 px rounded progress bar in the ink colour and the count of cards answered out of the session's cards, "15/20" at 14/700) above one scroll view: every card answered so far, then the current card ([ADR 0007](adr/0007-study-swipe-screen-and-session-toggle.md), [ADR 0023](adr/0023-scroll-the-current-study-card-with-the-stack-and-centre-each-half.md)). It shows no deck name and no answer button, and never builds the next card.
- Under the current card a hint row, outside the card's box so the card alone is placed, shows "모른다" after a red left chevron and "안다" before a green right chevron, at 13/600 in the muted colour; screen readers skip it, as the card's actions carry both answers ([ADR 0027](adr/0027-draw-both-clients-in-the-smartman-brand-and-the-v2-screens.md)).
- The current card:
  - sits full width less 20 on each side, last in the scroll view and painted over the stack, its centre at 57% of the screen height while it fits above the hint row when the view is at its end;
  - is rounded 24 with a two-layer soft shadow, and its halves are divided by a line that stops 28 short of the card's edges;
  - holds the question on its left half and the answer on its right, hidden until a tap and hidden again by the next; when a half would be narrower than 140 at the current text scale, the answer sits under the question, in two halves of the same height divided at the middle;
  - centres each half's content across and down while it fits, and shrinks the text, the question from 30 to 18 and the answer from 20 to 15, until its widest word fits the half, so a word breaks inside itself only past that floor (`CardText`, [`design.md`](design.md));
  - renders each side's content blocks through one block renderer, `ContentView`, the question at 30/800 and the answer at 20/600, with `UnsupportedContent` as a labelled placeholder;
  - grows with its content from 200 to 55% of the screen height, then each half scrolls inside, from the top.
- A horizontal drag of the current card moves and tilts it; past 40 a chip and a tint name the answer. Released past 100, or flung faster than 700 per second, it answers "Know" to the right and "Don't know" to the left, with a light haptic; otherwise it springs back. A vertical drag scrolls the view.
- The previous cards are every answer of the session, re-shows included, newest nearest the current card, built only near the view. Each is rounded 20 with a one-pixel line around it, and shows two lines of each side, centred in its half and shrunk from 16 to 12 until its widest word fits, an 8 px dot for its answer and "수정됨" once the answer differs from the first given; it is smaller, closer to the ground's colour and blurrier a step per card of depth up to a cap, unblurred past it, and opaque. A long-press opens the whole card in a sheet.
- The scroll view ([ADR 0023](adr/0023-scroll-the-current-study-card-with-the-stack-and-centre-each-half.md)):
  - opens at its end, and stays there as cards are added while it is there; fewer cards than fill it sit at its bottom;
  - dragged down, reveals earlier cards, the current card moving down with them;
  - returns to its end when an answer commits while it is scrolled back, at once under reduce motion; a swipe starts only on the part of the card on screen, and a screen reader's answer action brings the card into view first;
  - stays where it is on a toggle, one that puts its card back included.
- Tapping a previous card toggles its answer between "Know" and "Don't know", any number of times:
  - to "Don't know", a card's last answer puts the card back as a "Don't know" does, unless it is waiting or on screen;
  - to "Know", a card's last answer removes the card's re-show while it waits behind the card on screen;
  - any other toggle leaves the queue unchanged.
- On an answer the card flies off, the answered card rises into the stack and the next card emerges from below. Under the platform's reduce-motion setting, these become a 150 ms cross-fade.
- The session ends when the queue is empty or the user closes it, by the close button or by going back. The summary takes the current card's place, and may grow past a card's cap so its button stays in reach: the mascot in a brand-tint circle, "오늘 할 카드를 마쳤어요", when the next review is, three tiles (학습한 카드, the distinct cards answered; 안다 and 모른다, the answers standing as each, in green and red), "걸린 시간" from the first card to the end, and "덱으로 돌아가기".
  - The next review is the earliest due time among the cards answered, once the engine has scheduled every answer as it stands; it reads "오늘", "내일" or "n일 뒤" by calendar day. With no card answered the summary says there was nothing to study instead.
  - After the queue empties, the stack stays, and a toggle that puts a card back reopens the session with it.
  - After closing, the stack is gone and nothing can be toggled.
- Every string comes from the shared ARB set. The current card carries a label naming its front, and its back while shown, a tap action that shows or hides the answer, and the custom actions "안다" and "모른다". Each previous card's label names its front, back and answer, with a hint that a tap changes it.
- The screen's sizes and timings are constants in `app/lib/study/src/study_style.dart`. Its colours are the app theme's tokens, in the light or the dark theme, and its text styles come from the app theme ([`design.md`](design.md), [ADR 0011](adr/0011-shared-app-theme-bundled-font-and-today-builder.md)).

### Storage

- The `reviews` and `card_states` tables in `app/lib/shared/database.dart` belong to this domain. `card_states` holds each reviewed card's stability, difficulty, last review and due time; a new card has no row. Schema v2 added it ([ADR 0005](adr/0005-study-queue-and-card-state.md)).
- Every answer writes one `reviews` row (`good` for "Know", `again` for "Don't know", with its time, duration on screen and fuzz factor, which the answer draws from the session's `Random`). Schema v3 added `fuzz_factor`, checked to `[0, 1)`; a row written before it holds null, as its review was not fuzzed ([ADR 0012](adr/0012-fuzz-review-intervals.md)).
- Each write, after an answer or a toggle, replays the card's answers in this session as they stand, from its state when the session opened, one engine review per answer with that answer's fuzz factor. It then rewrites those `reviews` rows, keeping their ids, times and factors, and the card's `card_states` row, in one transaction ([ADR 0007](adr/0007-study-swipe-screen-and-session-toggle.md)). Each row it writes takes the write's time as `updated_at` and is left unsynced; sync pushes it, the server keeping a review's rating by the later `updated_at` ([`sync.md`](sync.md)).
- Schema v4 added `updated_at`, `deleted_at` and `dirty` to both tables. Reads leave out a card state with `deleted_at` set.
- The engine calls and the write run after the screen has changed, chained in the order given.
- `StudyRepository` receives its id generator, and the session its clock (`studyClockProvider`) and random source (`studyRandomProvider`), so tests fix all three.

### The bridge to the engine

- The app calls the engine ([`engine.md`](engine.md)) through flutter_rust_bridge 2.13.0, built with its native-assets backend ([ADR 0004](adr/0004-flutter-rust-bridge.md)).
- The bridge crate is `rust_lib_smartman` in `app/rust/`. It depends on `engine/` by path and declares the Dart surface in `app/rust/src/api/engine.rs`:
  - `review_new_card` — a new card's first review, with an optional fuzz factor;
  - `review_card` — a review of a card from its persisted state parts, with an optional fuzz factor;
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

- `app/test/study/engine_bridge_test.dart` calls the engine through the bridge. It checks one step of `engine/tests/fixtures/reference.json` without fuzz and one with, and the arrival of a refused review as an `EngineError`.
- `app/test/study/correction_test.dart` runs a session over an in-memory database and the real engine, and checks the state stored after each toggle against a chain of the bridge's `review_card` calls over the corrected history, from the state before the session. It also checks that toggling a fuzzed answer twice gives back the stored state, with the review's factor kept.
- `app/test/study/toggle_test.dart` covers the queue effects of a toggle; `app/test/study/queue_test.dart` covers the queue's membership over several decks, its order under seeded sources, the re-show gap, and a backlog: new cards taken at three days of reviews due and left out above, the earliest-due order with its tie, the shuffled runs of ten, and an up-to-date queue shuffled whole.
- `app/test/study/today_counter_test.dart` checks that the due and new counts add up to the length of the queue a session over the decks opens, in a backlog too, when the count is read again, and the pace: 10 s a card below 20 reviews, and the median of the latest 200 over older reviews that would move it.
- `engine/examples/backlog.rs` is the simulation that chose the backlog's order, run and threshold ([`engine.md`](engine.md)).
- `app/test/study/previous_cards_test.dart` checks that a stack of 300 answers above the current card builds only the cards near the view.
- `app/test/study/card_fit_test.dart` loads Pretendard, in a file of its own so the other tests keep the test font, and checks on a 390-wide current card that "meticulous", "incomprehensibility" and "once in a blue moon" shrink until their widest word fits, break only between words while the floor fits, and sit centred in their half.
- `app/test/study/study_screen_test.dart` drives the screen on a 390 by 844 view with a scheduler that answers at once, or a repository whose writes never finish, and checks it against the tap target and contrast guidelines in the light and the dark theme.
- `flutter test` loads the library from `app/rust/target/release/`, so `make test` builds the crate there first.

### Versions

- flutter_rust_bridge's release is pinned in `app/rust/Cargo.toml`, in `app/pubspec.yaml` for the runtime and hook packages, and, through `app/rust/Cargo.lock`, for the codegen. A bump of one alone fails `make ci`, so `.github/dependabot.yml` ignores `flutter_rust_bridge*` in the `/app` pub entry and the `/app/rust` cargo entry.
- The mover of flutter_rust_bridge is the PM: one PR bumps all three pins, regenerates the bindings, and commits what the codegen writes.
- `libc` is held at 0.2.189 in `app/rust/Cargo.lock`: with 0.2.190, `backtrace` fails to compile for iOS. `.github/dependabot.yml` ignores `libc` `= 0.2.190` in the `/app/rust` cargo entry. Upstream tracks the break in [rust-lang/libc#5601](https://github.com/rust-lang/libc/issues/5601). As of 2026-10-15 that issue is open, 0.2.190 is the latest 0.2 release, and the dyld fix ([rust-lang/libc#5606](https://github.com/rust-lang/libc/pull/5606)) is not merged.
- The ignore is dropped when a fixed `libc` release ships, after the macOS CI job passes on a PR that moves `app/rust/Cargo.lock` to it. A later release that still breaks the job is added to the ignore.
- Dependabot also proposes the bumps of `app/rust/rust-toolchain.toml`, which stays on the release of `engine/rust-toolchain.toml`.

## Rationale

- [ADR 0004](adr/0004-flutter-rust-bridge.md) records the bridge crate's place, the native-assets backend, the location of the bindings, and each departure from flutter_rust_bridge's documented layout.
- [ADR 0005](adr/0005-study-queue-and-card-state.md) records the queue policy, the re-show gap, why the state is stored as parts in `card_states`, and how `deck` opens the session.
- [ADR 0009](adr/0009-multi-deck-session-and-random-queue-order.md) records the session over several decks, the header card, the random order and gap, and why they supersede ADR 0005's.
- [ADR 0025](adr/0025-order-a-review-backlog-by-due-date-and-pause-new-cards.md) records the simulation, its results, and why a backlog is ordered earliest due first in shuffled runs of ten and pauses new cards above three days of reviews due.
- [ADR 0007](adr/0007-study-swipe-screen-and-session-toggle.md) records the swipe screen, the toggleable stack, and why a toggle replays the card's session answers in Dart rather than through the bridge's `replay`.
- [ADR 0023](adr/0023-scroll-the-current-study-card-with-the-stack-and-centre-each-half.md) records why the current card scrolls with the stack, what an answer or a toggle does while the view is scrolled back, and why each half of the card centres its content.
- [ADR 0027](adr/0027-draw-both-clients-in-the-smartman-brand-and-the-v2-screens.md) records the study screen's v2 look, the hint row, the summary's next review and why the today count carries the user's pace.
- [ADR 0011](adr/0011-shared-app-theme-bundled-font-and-today-builder.md) records why the screen's colours moved onto the app theme, and why `TodayCounter` shows its count through a builder `deck` supplies.
- [ADR 0012](adr/0012-fuzz-review-intervals.md) records where each answer's fuzz factor comes from and why it is stored on its review.
- Issue #9 records the surface the app needs and the requirement that every engine error reach Dart typed. Issue #12 records the first session flow, issue #18 the current screen, issue #56 the one scroll view and the centred halves, issue #19 the session over several decks, and issue #53 the backlog, as decided by the PM.
- [ADR 0015](adr/0015-sync-protocol-and-conflict-policy.md) records why sync recomputes a card's state through `Scheduler.fold` rather than merging states.

## Open questions

- Whether the header count should follow writes as they land rather than being read when the deck list returns on top. A write still running at that moment is missed until the next read (ADR 0009).
