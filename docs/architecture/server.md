# Server

The Supabase schema the app syncs to, and the extraction count beside it: its tables, row-level security, revisions, tombstones, and the tests that hold them.

## Current decisions

### Location and migrations

- The schema is defined by migrations in `supabase/migrations/`, applied in order by the Supabase CLI: `supabase db reset` locally, `supabase db push` to the remote project ([ADR 0010](adr/0010-server-schema-and-row-level-security.md)).
- `supabase/seed.sql` holds no rows; the tests insert their own.
- Only the PM pushes a migration to the remote project, after the pull request that adds it merges.

### Tables

- `public` holds `decks`, `cards`, `reviews` and `card_states`, mirroring the app's local tables (`app/lib/shared/database.dart`) with the same text ids, created on the device.
- `decks`, `cards` and `reviews` have `id` as primary key; `card_states` has `(user_id, card_id)`.
- Every row carries `user_id`, referencing `auth.users` with `on delete cascade`, so deleting an account deletes its rows. It defaults to the caller's `auth.uid()`.
- A card's `front` and `back` are `jsonb` arrays of blocks, in the encoding the app stores ([`deck.md`](deck.md)); a value that is not an array is refused.
- `cards.source` and `reviews.rating` take the local tables' values: `manual` or `import`, and `again` or `good`.
- `reviews.fuzz_factor` is the review's fuzz factor ([ADR 0012](adr/0012-fuzz-review-intervals.md)), null for a review scheduled without fuzz, and checked to `[0, 1)`. Migration `20261015120000_review_fuzz_factor.sql` added it.

### Sync columns

- `updated_at` — the device's edit time, set by the client; #24 orders concurrent edits by it.
- `deleted_at` — a tombstone, null while the row is live. Sync never deletes a row.
- `revision` — set on every insert and update by a trigger, from the one sequence `private.revision` shared by all four tables. Whatever the client sends is overwritten. Each table is indexed on `(user_id, revision)`, the pull cursor.
- Before drawing, the trigger takes a transaction-level advisory lock keyed by a 64-bit hash of the row's `user_id`, held until commit. One user's writing transactions therefore run one after another, so for each user a later commit holds the higher revision, and a pull by revision cannot pass a row that commits later. Different users never wait on each other, except on a hash collision ([ADR 0010](adr/0010-server-schema-and-row-level-security.md)).
- The cost: one user's concurrent writes, from two devices or two requests, serialize.
- The sequence and the trigger function live in the schema `private`, which the API does not expose. The function runs as its owner, so clients need no privilege on the sequence and have none.

### Access

- `anon` holds no privilege on the four tables; every statement it sends is refused.
- `authenticated` may select, insert, update and delete in `decks`, `cards` and `card_states`.
- `reviews` is insert-only for `authenticated`, except `rating` and `updated_at`, which a toggle changes ([ADR 0007](adr/0007-study-swipe-screen-and-session-toggle.md)). A client inserts `fuzz_factor` with its review and never changes it. A client cannot delete a review or set its `deleted_at`; a review goes only with its account, through the `auth.users` cascade.
- Row-level security is on for all four tables, with one policy per command allowing only rows where `user_id = auth.uid()`. The `reviews` delete policy exists but no client holds the privilege it would narrow.
- The privileges are granted in the migration, not left to the project's default privileges.
- The app does not use the service role.

### Extraction usage

- `public.extraction_usage` holds one row per photo extraction the `extract-cards` function let through: an identity `id`, `user_id` referencing `auth.users` with `on delete cascade`, and `created_at` ([`ai-extraction.md`](ai-extraction.md), [ADR 0013](adr/0013-extract-cards-function-and-eval.md)).
- It is not synced: it has no revision, tombstone or edit time.
- `authenticated` may only select it, and row-level security allows only the caller's rows, so the app can read today's count. `anon` holds nothing.
- Rows are written only by `public.consume_extraction(user_id, daily_limit)`, executable only by `service_role`. It takes a transaction-level advisory lock on the user, counts the rows since the start of the UTC day, and inserts one and returns true under the limit, or returns false. `service_role` itself may not insert directly.
- The lock's key is the hash of the user id seeded with 1, never the revision lock's seed 0.
- The migration adding it is additive: it creates the table, its index and the function, and changes nothing that existed.

### Integrity

- A card's deck, and a review's or card state's card, belong to the row's own user. Composite foreign keys enforce it: `cards (user_id, deck_id)` references `decks (user_id, id)`, and `reviews` and `card_states` reference `cards (user_id, id)`, each with `on delete cascade`.

### Tests

- pgTAP tests in `supabase/tests/`, one file per concern, run by `supabase test db`:
  - `rls_test.sql` — user A selects, inserts, updates and deletes its own rows and none of user B's, in each table;
  - `reviews_test.sql` — a client changes a review's rating and nothing else, and deletes no review;
  - `anon_test.sql` — `anon` is refused on every table, with an authenticated read as control;
  - `revision_test.sql` — `revision` comes from the sequence on insert and update, whatever the client sends;
  - `revision_lock_test.sql` — a write to each table holds its user's advisory lock, and only that user's;
  - `integrity_test.sql` — references to another user's deck or card are refused;
  - `extraction_usage_test.sql` — users read only their own usage rows and write none, and `consume_extraction` lets a user through until the daily limit, under that user's lock alone;
  - `fuzz_factor_test.sql` — a review's fuzz factor is checked to `[0, 1)` and inserted by its client, which cannot update it, with an update of the rating as control.
- `make test` runs `supabase/test-db.sh`. Where Docker answers, it starts a throwaway stack of its own with only Postgres, which applies the migrations, runs the tests and prints their count ([ADR 0014](adr/0014-database-tests-on-a-stack-of-their-own.md)). Where Docker does not, it prints that the tests were skipped and why.
- The throwaway stack is named `smartman_test_<port>` and publishes its database on the first port in 54400–54499 that the run reserves under `${TMPDIR:-/tmp}/smartman-test-db/` and that nothing listens on. Concurrent runs, from several checkouts on one host, each get their own, and none touches the `smartman` stack or its rows.
- The script stops its stack, deleting its data, on every exit, interrupts included, and retries a stop that fails because another stack is stopping at the same moment. A stack it cannot stop fails the run, which prints how to remove it. A run killed with `SIGKILL` leaves its stack and reservation behind, to remove by hand.
- CI's ubuntu job installs the Supabase CLI and runs them; the macOS runner has no Docker, so its log shows the skip.
- `make test` then runs `supabase/test-sync.sh`, the two-device sync test against a throwaway stack with Auth and PostgREST ([`sync.md`](sync.md)).

## Rationale

- [ADR 0010](adr/0010-server-schema-and-row-level-security.md) records the schema, the access rules and the revision mechanism.
- [ADR 0013](adr/0013-extract-cards-function-and-eval.md) records why the extraction count is a table written through one locked function.
- [ADR 0014](adr/0014-database-tests-on-a-stack-of-their-own.md) records why the tests run on a throwaway stack per run, superseding ADR 0010's "Tests" decision.
- [ADR 0015](adr/0015-sync-protocol-and-conflict-policy.md) records how sync pushes reviews within the column grant, and the two-device test's stack.
- Issue #23 records the decisions made by the PM; issue #25 records those for the extraction count, and issue #24 the fuzz factor column.

## Open questions

- None.
