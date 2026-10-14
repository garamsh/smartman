# ADR 0012: Fuzz review intervals as py-fsrs 6.3.2 does, with a factor the app draws and stores on each review

> Status: accepted
> Date: 2026-10-15

Append-only: once merged, the body below is not rewritten. A fact later found wrong is corrected in an appended note, not edited out; a revised decision is a new ADR that supersedes this one.

## Context

- The owner asked (2026-10-15) that users must not be able to memorize the order cards come in. [ADR 0009](0009-multi-deck-session-and-random-queue-order.md) shuffles the order within a session. [ADR 0003](0003-fsrs-engine.md) left fuzz out, so cards studied together stay due together, and the next session shows them together again.
- Issue #27 records the PM's decisions:
  - the fuzz is py-fsrs 6.3.2's, with its interval ranges and its rule that only intervals of at least 2.5 days are fuzzed;
  - the engine stays pure: it takes a fuzz factor in `[0, 1)` and draws nothing, and `review`, `review_card` and `review_new_card` take it as optional, none meaning no fuzz;
  - the app draws the factor from the session's injected `Random`, and a toggle replay ([ADR 0007](0007-study-swipe-screen-and-session-toggle.md)) reuses each review's original factor, stored on its review row;
  - the existing reference values still pass unchanged, and new fixtures record py-fsrs's factor per review under fixed seeds.
- py-fsrs v6.3.2 (tag `v6.3.2`, commit `9446cb06605c597a063aeee49f7d188d42e34dc2`), `fsrs/scheduler.py`:
  - `FUZZ_RANGES` widens the range by 0.15 days per interval day from 2.5 to 7, 0.1 from 7 to 20, and 0.05 past 20, on top of 1 day;
  - `Scheduler._get_fuzzed_interval` returns an interval under 2.5 days unchanged. Otherwise it rounds the interval less and plus that width to the range ends, at least 2 and at most the maximum interval. It picks `round(random() * (max - min + 1) + min)`, capped at the maximum interval, so the greatest factor can land one day past the upper end;
  - `Scheduler.review_card` fuzzes whenever the card ends the review in the Review state, which, with no learning or relearning steps, is every review;
  - the factor comes from the module-level `random()`, one call per fuzzed interval.
- The server schema (issue #23, PR #32) had not merged when this was decided, so the server has no review table to carry the factor yet.

## Decision

- **Formula.** The engine fuzzes an interval as `Scheduler._get_fuzzed_interval` does at that tag, ranges and rounding included, when the caller passes a factor. It does not fuzz without one, and its results are then those of [ADR 0003](0003-fsrs-engine.md).
- **Factor.** The factor is a typed input in `[0, 1)`; a value outside it is refused as an `OutOfRange` or `NonFinite` error of the quantity `FuzzFactor`. Fuzz moves only the due time: the state, and so `replay`, does not depend on it.
- **Source.** Each answer in a session draws its factor from the session's `Random`, the source of ADR 0009's draws. The review keeps it, a toggle keeps it, and every replay of the card's session answers schedules each with its own.
- **Storage.** The local `reviews` table gains a nullable `fuzz_factor` column (schema v3), checked to `[0, 1)`. A row written before v3 holds null, as its review was scheduled without fuzz. The server column waits for the server schema to merge.
- **Reference values.** `engine/tests/fixtures/generate.py` also runs each sequence with fuzzing under seeds 1 and 2, standing a seeded source in for py-fsrs's `random`, and records the factor each review drew.

## Consequences

- Cards answered together in a session fall due on different days once their intervals reach three days, so a later session does not bring the same group back.
- A toggle, any number of times, recomputes the same due time for an unchanged history, and toggling twice gives back the stored state.
- Tests stay deterministic: a seeded or constant `Random` fixes every factor, and a source that always draws 0 gives the low end of each range.
- An interval of one or two days is never fuzzed, so new cards answered "Know" together are still due together on day two.
- A review row's factor is part of its history. Recomputing a card from its stored reviews needs the factor of each, and a v2 row's null means none.
- The engine follows py-fsrs's reference rather than a published description for fuzz, as it already does for the four points ADR 0003 lists.

## Signs the decision was wrong

- Users still report recognising a recurring group of cards, among those whose intervals are under three days.
- Spreading due dates makes daily counts uneven enough that users ask for load balancing, which py-fsrs leaves out and issue #27 puts out of scope.
- A later py-fsrs release changes its fuzz ranges or rounding, and the engine has to follow it again.
- Sync or server-side rescheduling needs the factor and finds reviews without it, beyond the v2 rows this ADR accepts as unfuzzed.
