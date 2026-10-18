# ADR 0061: Keep a card failed today in today's list until it is passed, through a pure engine function over the day's reviews

> Status: accepted
> Date: 2026-10-18

Append-only: once merged, the body below is not rewritten. A fact later found wrong is corrected in an appended note, not edited out; a revised decision is a new ADR that supersedes this one.

## Context

- Issue #195 records the owner's decision of 2026-10-18, after weighing it with the PM: a card failed today is shown again today. Finishing today's learning is not part of the long-term memory model.
- **FSRS stays.** [ADR 0003](0003-fsrs-engine.md) keeps FSRS-6 with whole-day intervals and no learning steps, validated against py-fsrs 6.3.2. It left same-day re-shows to the session queue (M3).
  - A re-show held only in a session's memory is lost when the screen closes.
  - A card answered "Don't know" falls due a day or more later, so a reopened session never shows it again that day. Issue #194 reports the count shrinking for the same reason.
- **One implementation.** The app, the web and the server each need today's list. Issue #196 weighed a new engine; it was closed on 2026-10-18 for this function.
  - ADR 0003's first sign that it was wrong is "the session queue grows its own Learning/Relearning state machine". Writing one in each client would be exactly that, twice.
  - The engine crate is the one implementation all three already share (`engine/`, the bridge in `app/rust/`, the WebAssembly in `engine-wasm/`).
- **What it needs is already stored.** Each answer, a same-day re-show included, is a `reviews` row, and each card's due time is in `card_states`. Whether a card was failed today and not passed since is a fact the log holds.
- Alternatives considered:
  - **py-fsrs's learning and relearning steps.**
    - They need a step state stored per card, and a migration on the device and in Supabase.
    - They change the validated FSRS reference and the sync, while the log already holds the fact.
    - A card answered "Know" still leaves the list, so they would not stop #194's count shrinking.
  - **A stored plan of the day's cards** (the owner's first design on #194): a second copy of what the log holds, which could disagree with it.
  - **The rule in each client's session code**: three implementations to keep alike.

## Decision

- **The split.** Long-term memory stays FSRS-6 as ADR 0003 has it: every answer, re-shows included, is a review the engine replays. Today's learning is a separate, pure function in the engine crate.
- **`today(due, reviews, day)`** in `engine/src/today.rs` places one card in a study day's list:
  - **Left:** its latest review in the day is `Again` ("Don't know"), or it is not reviewed in the day and falls due before the day ends.
  - **Done:** its latest review in the day is rated above `Again` ("Know").
  - **Absent:** neither, including a card never reviewed and not answered that day.
  - **Inputs:** the card's due time, `None` without a state; its reviews in any order, two at one time taken in the order given; and the `StudyDay`.
    - The day's bounds come from the caller: the app's 04:00 to 04:00 in the device's zone (ADR 0033). The start is inclusive and the end exclusive.
    - Reviews outside the day are ignored. Of two at one time, the later given counts.
  - **No clock and no error:** the function reads no clock and returns no error. A day whose end is not after its start holds no review, and FSRS's functions are untouched.
- **Exported** through the bridge as `todays_list(cards, day_start, day_end)`, and through WebAssembly as `todaysList(cards, dayStart, dayEnd)`. Each takes a list of cards, each with its due time and reviews, and returns each card's place in the order given.
  - Dart calls the bridge's `todays_list` synchronously: the function is pure and cheap, and a widget test's fake clock can run a synchronous call where it cannot complete a port's reply.
- **What the caller does.**
  - **Done is any card whose latest review in the day is above `Again`.** That includes a new card first answered that day and a card studied past today's cards (ADR 0049). A day's done cards, and so its total, grow with study beyond the day's queue. This is #195's "latest answer Know", read for the engine's ratings.
  - **New cards still to come from the day's quota are `Absent`.** The engine knows no quota, and the caller adds them, as the app's and the web's queue rules do (ADR 0033, ADR 0043).
  - **Deleted reviews are the caller's to leave out.** A tombstoned review passed in counts like any other.
- **No schema change and no Supabase change.** The function reads only the rows the app and the web already keep.
- **Supersession.** This replaces ADR 0003's learning and relearning left to the session queue alone. A card failed today stays in today's list through this function, while the order of re-shows within a session stays the queue's. ADR 0003's memory model, intervals and absence of learning steps stand.

## Consequences

- A card failed today comes back today in every client, across sessions, until it is passed. Its stored state, due a day or more later, is unchanged.
- The engine has two surfaces, FSRS's scheduling and today's list. Neither reads the other's output, so FSRS's reference tests are unaffected.
- Every client that shows today's work has to pass the day's reviews in, so each reads `reviews` since 04:00. The app and the web already read them for their counts.
- The server can compute the same list from the same rows when it needs one.

## Signs the decision was wrong

- Users find cards failed early in the day coming back too often, or never ending. The rule would then need a cap the engine does not have.
- A card's state and today's list disagree in ways users see, such as a card shown as due again today whose state is due next week.
- A client builds today's list without this function and the counts differ between the app and the web.
