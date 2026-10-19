# ADR 0015: Sync in the background by pull then push per table, with last-writer-wins edits, winning tombstones, unioned reviews and recomputed card states

> Status: accepted; its `syncStatusProvider` superseded by ADR-0039; the local `deleted_at` on `reviews` and `card_states` superseded by ADR-0077
> Date: 2026-10-15

Append-only: once merged, the body below is not rewritten. A fact later found wrong is corrected in an appended note, not edited out; a revised decision is a new ADR that supersedes this one.

## Context

- Issue #24 (M5b) syncs decks, cards, reviews and card states between devices through the server schema of [ADR 0010](0010-server-schema-and-row-level-security.md). goal.md M5 asks for a conflict policy. The PM decided in the issue:
  - local schema v4: `updated_at`, `deleted_at` and a `dirty` flag on each synced table, and a `sync_state` table holding the per-table pull cursor;
  - a review's `fuzz_factor` ([ADR 0012](0012-fuzz-review-intervals.md)) syncs with it: a nullable server column checked to `[0, 1)`, insertable by clients and not updatable;
  - push upserts dirty rows and clears `dirty` when acknowledged; pull takes rows above the cursor, per table, paged, applied in a drift transaction;
  - decks and cards: last writer wins by `updated_at`, a tombstone winning over a concurrent edit; reviews: a union by id, a rating change following last-writer-wins; card states never merged but recomputed by folding a card's reviews through the engine after a pull brings one; equal-key cards both kept;
  - sign-in is required to use the app (owner decision, 2026-10-15; the gate is #28), so the local database belongs to the signed-in account: rows from before the gate join the first account, sign-out pushes, warns when it cannot, then clears, and a database another account owns is cleared and never pushed;
  - sync runs after sign-in, at start and resume, after a session, and after an edit, never on the answer path, with typed failures retried with backoff;
  - a new `app/lib/sync/` domain, using `account`'s surface for the session and `study`'s for the fold, which `deck` and `study` do not import.
- [ADR 0006](0006-account-native-google-sign-in.md) made `account` the only domain importing `supabase_flutter`. Sync needs PostgREST with the signed-in session.
- `reviews` grants clients `update (rating, updated_at)` only (ADR 0010). Postgres requires the update privilege on every column an `INSERT … ON CONFLICT DO UPDATE` sets, so a plain upsert of a whole review is refused; `ON CONFLICT DO NOTHING` needs none.
- The local database stores times in whole seconds, so two edits in one second carry equal `updated_at`.
- The server has no conditional write for decks and cards that a row-level policy can express, and ADR 0010 lists moving merges into a function that bypasses the policies as a sign it was wrong.

## Decision

- **Order.** A run claims the database for the account, pulls every table, recomputes the states of cards whose reviews changed, then pushes. Pulling first means a local row that loses its merge is overwritten before it could be sent.
- **Merge.** Each pulled row is merged with the local one as the issue decides. On equal `updated_at`, an unsynced local edit wins, because the server has not seen it; otherwise the server's. Where the local copy is kept, it is marked unsynced, so the next push corrects a server copy that another device's older write replaced.
- **Card states.** A pulled state replaces a synced local one and gives way to an unsynced one; the fold after the pull then overwrites either, unsynced, where it differs.
- **Pushing reviews.** New reviews are inserted with `ON CONFLICT DO NOTHING`; each review the server already held then gets its `rating` and `updated_at` by an update filtered to rows whose `updated_at` is older.
- **Acknowledgement.** `dirty` is cleared only on a row still equal to the row pushed.
- **Parents.** A pulled row whose parent has not arrived ends its page below the cursor; the pull is repeated, up to three passes.
- **Ownership.** `sync_state` holds the owning account's id with the cursors, in one row. Every pushed row carries the run's `user_id`, so row-level security refuses it if the session has changed accounts.
- **Triggers.** The controller follows the account state, the app lifecycle, and drift's table updates, debounced by three seconds and run only when a row is unsynced. A session's answers are local writes, so no `study` code calls sync. Failures back off from 5 seconds, doubling, to 5 minutes.
- **Boundary.** `connectAccount` returns the `SupabaseClient` with the service; `sync`'s `SupabaseSyncServer`, behind the `SyncServer` seam, imports `supabase_flutter` for PostgREST. This supersedes ADR 0006's "It is the only domain importing `supabase_flutter`"; `google_sign_in` stays `account`'s alone. `account` reaches sync through `accountDataProvider` and `syncStatusProvider`, which the composition site overrides.
- **Integration test.** `supabase/test-sync.sh` runs `app/test/sync/two_devices_test.dart` against a throwaway stack with Auth, PostgREST and the gateway, reserving its database and API ports as [ADR 0014](0014-database-tests-on-a-stack-of-their-own.md) does.

## Consequences

- Two devices converge after each has synced once more than the other: an edit pushed over a newer one is undone by the next pull on the device holding the newer.
- A delete cannot be undone by another device's later edit, and a deleted deck or card stays on the server as a tombstone.
- A pull can write rows that the next push sends back unchanged, such as a recomputed card state equal to the server's.
- Same-second edits on two devices resolve to the one pushed last, not the one made last.
- A review's history stays on the server even after its card is deleted, since clients cannot tombstone reviews.
- `make test` starts a second throwaway stack, with Auth and PostgREST, after the database tests.

## Signs the decision was wrong

- Devices keep pushing the same row back and forth, which would mean two merges that each keep their own copy.
- Users see an edit they made undone by another device's edit made earlier in the same second, often enough to complain.
- Pulls fail on missing parents after three passes, which would mean writes reaching the server out of order.
- A recomputed card state on one device differs from another's for the same reviews, which would mean the fold depends on more than the reviews and their factors.
- The sign-out warning appears while online, which would mean `push` leaves rows unsynced that a run should have sent.
