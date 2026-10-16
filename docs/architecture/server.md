# Server

The Supabase schema the app syncs to, and the extraction count beside it: its tables, row-level security, revisions, tombstones, account deletion, and the tests that hold them.

## Current decisions

### Location and migrations

- The schema is defined by migrations in `supabase/migrations/`, applied in order: by the Supabase CLI's `supabase db reset` locally ([ADR 0010](adr/0010-server-schema-and-row-level-security.md)), and by Supabase's GitHub integration on the remote project.
- `supabase/seed.sql` holds no rows; the tests insert their own.
- **Deploy path.** `main` is the deployed state. When a pull request adding a migration merges into `main`, Supabase's GitHub integration applies the migration to the production project; no one runs `supabase db push`. Its `Supabase Preview` check on the merge commit records the run.
  - Measured: #115's merge `9b98292d2f642e794e5d32d969e3999629c5964b` at 13:55:55Z on 2026-10-16, with `Supabase Preview` running 13:56:27–13:56:35Z; #118's merge `a940deaef30ca376e34cd83631bd4112055cda6a` at 15:41:51Z, with the check 15:42:24–15:42:33Z. A `supabase db push` minutes after #115's merge reported "Remote database is up to date" (issue #117).
  - To confirm a migration reached production: the `Supabase Preview` check succeeded on the merge commit, and `supabase migration list --linked` lists the migration's version in its remote column.
- **Gate.** A pull request whose migration changes or deletes existing data merges only after the owner approves it, since merging deploys it; the PM asks with the reviewed pull request in hand. An additive migration needs no such approval, but it is deployed as merged, so it must be correct then. Workers make no change to the remote project.

### Tables

- `public` holds `decks`, `cards`, `reviews` and `card_states`, mirroring the app's local tables (`app/lib/shared/database.dart`). Their ids are created on the device.
- `decks`, `cards` and `reviews` have `id` as primary key; `card_states` has `(user_id, card_id)`.
- Every synced id, and every column that references one, is `uuid`: `decks.id`, `cards.id`, `cards.deck_id`, `cards.origin_deck_id`, `reviews.id`, `reviews.card_id`, `card_states.card_id`, `deck_reports.deck_id` and `deck_imports.deck_id`. No id column has a default, so a row sent without an id is refused. `extraction_usage.id` is an identity ([ADR 0034](adr/0034-key-synced-rows-by-client-made-uuids-purge-tombstones-past-a-revision-horizon-and-index-each-query.md)).
- Migration `20261016180000_uuid_keys.sql` cast those columns from `text` in place, so every row kept its id. It first raises, changing nothing, unless every value is in canonical lowercase form, the only form Postgres returns unchanged, so the phone, which keeps ids as text, holds the same id the server returns ([`sync.md`](sync.md)). In one transaction it dropped the five foreign keys and the two policies that name those columns, cast them, and recreated the keys, the policies, `list_public_decks` and `record_deck_import`.
- PostgREST sends a uuid as the same JSON string a text id was, so app and web versions released before the conversion keep working.
- Every row carries `user_id`, referencing `auth.users` with `on delete cascade`, so deleting an account deletes its rows. It defaults to the caller's `auth.uid()`.
- A card's `front` and `back` are `jsonb` arrays of blocks, in the encoding the app stores ([`deck.md`](deck.md)); a value that is not an array is refused.
- `cards.source` and `reviews.rating` take the local tables' values: `manual`, `import` or `shared`, and `again` or `good`. Migration `20261015180000_public_decks.sql` widened the source check to `shared` in one statement, changing no row ([ADR 0020](adr/0020-public-decks-in-a-sharing-domain.md)).
- `cards.origin_deck_id` is a copied card's source deck, with no foreign key, since that deck is another user's.
- `reviews.fuzz_factor` is the review's fuzz factor ([ADR 0012](adr/0012-fuzz-review-intervals.md)), null for a review scheduled without fuzz, and checked to `[0, 1)`. Migration `20261015120000_review_fuzz_factor.sql` added it.

### Public decks

- `decks.visibility` is `private` (the default) or `public`; a public deck has `published_at`. `decks.description` is at most 300 characters. These sync like the deck's name ([`sharing.md`](sharing.md)).
- `decks.hidden` and `decks.import_count` are the server's: clients read them and cannot write them.
- `public.profiles` holds one display name per user, 2 to 20 characters with no surrounding whitespace. Users insert and update their own; anyone signed in reads the name of a user with a visible public deck.
- `public.deck_reports` holds one report per reporter and deck, with a reason: `inappropriate`, `spam`, `copyright` or `other`. A user inserts a report only as itself, on a visible public deck of another user, and reads none back.
- A trigger hides a deck once three distinct users reported it, under an advisory lock on the deck seeded with 2, so concurrent reports are counted one after another. The lock's key hashes the deck's id as text, so the key a deck took before the ids were `uuid` is the key it takes now. The project's owner unhides it in the dashboard.
- `public.user_blocks` holds a user's blocks; users select, insert and delete their own.
- `list_public_decks(search, sort, page_size, page_offset)` runs as the caller and lists visible public decks not of a user the caller blocked, whose name or description holds the search ignoring case, newest first or most copied first, with the owner's display name and live card count. It returns each deck's id as `uuid`.
- `record_deck_import(deck_id uuid)` runs as its owner: it returns false for a deck that is not visibly public, and otherwise true. A caller's first copy of a deck it does not own inserts a row in `public.deck_imports` and adds one to `import_count`; a later copy by that caller, or a copy by the owner, changes neither (issue #67).
- `public.deck_imports` holds one row per deck and user who copied it, keyed by the two, so concurrent copies by one user insert one row and add one between them. Clients hold no privilege on it, and row-level security is on with no policy. Removing a row, with its deck or its account, leaves `import_count` as it is.
- Copies made before `deck_imports` existed were not recorded per user, so their counts stay as they were and later copies add to them. Migration `20261016090000_deck_imports.sql` is additive: it creates the table and replaces the function with the same signature, changing no row.
- A deck is visibly public when it is public, not hidden and not deleted.

### Sync columns

- `updated_at` — the device's edit time, set by the client; #24 orders concurrent edits by it.
- `deleted_at` — a tombstone, null while the row is live. Sync never deletes a row.
- `revision` — set on every insert and update by a trigger, from the one sequence `private.revision` shared by all four tables. Whatever the client sends is overwritten. Each table is indexed on `(user_id, revision)`, the pull cursor.
- Before drawing, the trigger takes a transaction-level advisory lock keyed by a 64-bit hash of the row's `user_id`, held until commit. One user's writing transactions therefore run one after another, so for each user a later commit holds the higher revision, and a pull by revision cannot pass a row that commits later. Different users never wait on each other, except on a hash collision ([ADR 0010](adr/0010-server-schema-and-row-level-security.md)).
- The cost: one user's concurrent writes, from two devices or two requests, serialize.
- The sequence and the trigger function live in the schema `private`, which the API does not expose. The function runs as its owner, so clients need no privilege on the sequence and have none.

### Access

- `anon` holds no privilege on the four tables; every statement it sends is refused.
- `authenticated` may select, insert, update and delete in `cards` and `card_states`, and select and delete in `decks`. On `decks` it may insert and update every column but `hidden` and `import_count`.
- `reviews` is insert-only for `authenticated`, except `rating` and `updated_at`, which a toggle changes ([ADR 0007](adr/0007-study-swipe-screen-and-session-toggle.md)). A client inserts `fuzz_factor` with its review and never changes it. A client cannot delete a review or set its `deleted_at`; a review goes only with its account, through the `auth.users` cascade.
- Row-level security is on for all four tables, with one policy per command allowing only rows where `user_id = auth.uid()`. The `reviews` delete policy exists but no client holds the privilege it would narrow.
- The one select policy of `decks` and of `cards` also lets any signed-in user read a visibly public deck and its live cards, and that of `profiles` the name of a user with one. Each tests the owner's condition first and ORs in the public one, so a read of one's own rows never runs the public condition's subquery ([ADR 0034](adr/0034-key-synced-rows-by-client-made-uuids-purge-tombstones-past-a-revision-horizon-and-index-each-query.md) §7). Migration `20261016200000_checks_and_policies.sql` merged each table's former owner and public pair into it, changing no row's visibility. Writes stay the owner's, since no write policy names another user's rows.
- Every policy names `to authenticated` and reads `(select auth.uid())`. A pull therefore filters on its account's `user_id` ([`sync.md`](sync.md)).
- The privileges are granted in the migration, not left to the project's default privileges.
- `record_deck_import` runs as `security definer` and `authenticated` may execute it, which the Security Advisor reports as lint `0029_authenticated_security_definer_function_executable`. That is intended: it writes `deck_imports` and `import_count`, which no client may write, and [ADR 0034](adr/0034-key-synced-rows-by-client-made-uuids-purge-tombstones-past-a-revision-horizon-and-index-each-query.md) §7 lists it among the `security definer` functions, granted to the one role that calls it (issue #113).
- The app does not use the service role.

### Extraction usage

- `public.extraction_usage` holds one row per photo extraction the `extract-cards` function let through: an identity `id`, `user_id` referencing `auth.users` with `on delete cascade`, and `created_at` ([`ai-extraction.md`](ai-extraction.md), [ADR 0013](adr/0013-extract-cards-function-and-eval.md)).
- It is not synced: it has no revision, tombstone or edit time.
- `authenticated` may only select it, and row-level security allows only the caller's rows, so the app can read today's count. `anon` holds nothing.
- Rows are written only by `public.consume_extraction(user_id, daily_limit)`, executable only by `service_role`. It takes a transaction-level advisory lock on the user, counts the rows since the start of the UTC day, and inserts one and returns true under the limit, or returns false. `service_role` itself may not insert directly.
- The lock's key is the hash of the user id seeded with 1, never the revision lock's seed 0.
- The migration adding it is additive: it creates the table, its index and the function, and changes nothing that existed.

### Account deletion

- The `delete-account` Edge Function deletes the caller's user from `auth.users` through Supabase Auth's admin API, with the service-role key, which stays in the function ([`account.md`](account.md), [ADR 0026](adr/0026-delete-the-account-through-an-edge-function.md)). The deletion is hard, so the cascade runs.
- Every table in `public` deletes with the user: `decks`, `cards`, `reviews`, `card_states`, `extraction_usage` and `profiles` by `user_id`, `deck_reports` and `deck_imports` by their user and by their deck, and `user_blocks` by either side. Another user's copy of a deleted user's deck stays theirs.
- A new table holding a user id references `auth.users` with `on delete cascade`.
- Only the PM deploys the function, after the pull request that adds or changes it merges.

### Integrity

- A card's deck, and a review's or card state's card, belong to the row's own user. Composite foreign keys enforce it: `cards (user_id, deck_id)` references `decks (user_id, id)`, and `reviews` and `card_states` reference `cards (user_id, id)`, each with `on delete cascade`.

### Checks

- Besides the column checks above, five checks hold on every row ([ADR 0034](adr/0034-key-synced-rows-by-client-made-uuids-purge-tombstones-past-a-revision-horizon-and-index-each-query.md) §5):
  - `decks_name_check`: `deleted_at is not null or name <> ''`;
  - `cards_card_key_check`: `deleted_at is not null or card_key <> ''`;
  - `card_states_stability_check`: `stability >= 0.001`;
  - `card_states_difficulty_check`: `difficulty between 1 and 10`, the engine's clamps with the one above;
  - `cards_origin_deck_id_check`: `(source = 'shared') = (origin_deck_id is not null)`.
- A tombstone may have an empty name or card key, since the purge strips them.
- Migration `20261016200000_checks_and_policies.sql` added them. It first counts each check's failing rows and raises, changing nothing, unless every count is zero. It then adds each `not valid` and validates it, in the same transaction, so the lock the addition takes lasts to commit. A table large enough for that lock to matter is validated in a later migration.
- **Constraint names.** Constraints keep Postgres's default names (`_pkey`, `_key`, `_fkey`, `_check`), and a constraint added later is given its name explicitly in that form.
- A row a check refuses fails a sync run as `SyncFailed` ([`sync.md`](sync.md)).

### Indexes

- Each index serves a named query, and a new query names its index or why it has none ([ADR 0034](adr/0034-key-synced-rows-by-client-made-uuids-purge-tombstones-past-a-revision-horizon-and-index-each-query.md) lists them). Migration `20261016150000_server_indexes.sql` added these, changing no row:
  - `reviews_live_user_id_reviewed_at` on `(user_id, reviewed_at)` where `deleted_at is null`, for the pace and a study day's reviews;
  - `cards_deck_id_created_at_id` on `(deck_id, created_at, id)`, for the composite foreign key's cascade, a study selection's cards, the public preview and the public listing's card count. It is not partial, so the cascade finds tombstones. It replaced `cards_user_id_deck_id`, which the migration dropped;
  - `deck_reports_reporter_id`, `user_blocks_blocked_id` and `deck_imports_user_id`, for the account-deletion cascade;
  - `decks_tombstone_revision`, `cards_tombstone_revision` and `card_states_tombstone_revision` on `revision` where `deleted_at is not null`, for the purge.
- **Index names** are `{table}_[{predicate}_]{columns}`. The predicate is `live` (`deleted_at is null`), `tombstone` (`deleted_at is not null`) or `public` (visibly public).
- Indexes are created with plain `create index` in a migration.

### Target data model (not built yet)

[ADR 0034](adr/0034-key-synced-rows-by-client-made-uuids-purge-tombstones-past-a-revision-horizon-and-index-each-query.md) decides the schema below. None of it is built yet: each bullet holds once the migration that its implementation issue adds has been applied. Until then the decisions above describe the database.

- **Key versions.** New ids are version 7; rows created before that keep their version 4 ids ([`sync.md`](sync.md)).
- **Time.** Every time column is `timestamptz`, as today. `updated_at`, `created_at`, `reviewed_at` and `deleted_at` stay the client's, at millisecond precision. `revision` stays the server's.
- **Tombstone purge.** `private.revision_marks` records the sequence's last value once a day. A `pg_cron` job then purges the `decks`, `cards` and `card_states` tombstones whose `revision` is at or below the mark taken 90 days earlier, and stores that mark as the horizon in `private.sync_horizon`. `public.sync_horizon()` returns the horizon to `authenticated` ([`sync.md`](sync.md)). The job also deletes `cron.job_run_details` rows older than 30 days.
  - Study history survives deletion (the owner's decision, issue #93). A card tombstone that reviews reference keeps its row, stripped of `front`, `back` and `card_key`, so its reviews stay in the streak and the statistics. One that no review references is deleted, and so is every card state tombstone.
  - A deck tombstone is deleted once no card row references it. Until then it keeps its row, stripped of its name and description and made private.
  - Only account deletion removes reviews and the kept rows.
- **Functions** run as `security invoker` unless they must reach what the caller cannot. Each `security definer` function sets `search_path = ''` and revokes `execute` from `public`. The definer functions are the revision trigger, `consume_extraction`, `hide_reported_deck`, `record_deck_import`, `sync_horizon` and the purge.
- **Public listing.** Search stays a scan, matching `strpos` on `lower()`, until a threshold in ADR 0034 is crossed; then a `pg_trgm` GIN index on the visibly public decks serves it. The card count stays a correlated count.
- **Watching.** After each applied migration, the PM reads Supabase's Security and Performance Advisors, and monthly reads `supabase inspect db outliers` and `index-stats`. Each lint is fixed or recorded in an issue.

### Streak

- `public.study_streak_before(time_zone, before)` returns how many study days in a row before the one holding `before` hold one of the caller's live answers, with days from 04:00 to 04:00 in the zone named, as `web/src/features/study/queue.ts` counts them ([ADR 0034](adr/0034-key-synced-rows-by-client-made-uuids-purge-tombstones-past-a-revision-horizon-and-index-each-query.md) §4). The web's `readToday` calls it ([`web.md`](web.md)).
- It walks back one day at a time from local 04:00 to local 04:00, so a day across a change of offset keeps both ends, and stops at the first day without an answer. Each day is one backward probe of `reviews_live_user_id_reviewed_at` for its latest answer.
- It is `security invoker`, so row-level security decides what it reads, `stable`, and sets `search_path = ''`. `execute` is revoked from `public` and `anon` and granted to `authenticated`. A zone Postgres does not know raises `22023`.
- Migration `20261017090000_study_streak.sql` added it, changing no row.

### Tests

- pgTAP tests in `supabase/tests/`, one file per concern, run by `supabase test db`:
  - `rls_test.sql` — user A selects, inserts, updates and deletes its own rows and none of user B's, in each table;
  - `reviews_test.sql` — a client changes a review's rating and nothing else, and deletes no review;
  - `anon_test.sql` — `anon` is refused on every table, with an authenticated read as control;
  - `revision_test.sql` — `revision` comes from the sequence on insert and update, whatever the client sends;
  - `revision_lock_test.sql` — a write to each table holds its user's advisory lock, and only that user's;
  - `integrity_test.sql` — references to another user's deck or card are refused;
  - `extraction_usage_test.sql` — users read only their own usage rows and write none, and `consume_extraction` lets a user through until the daily limit, under that user's lock alone;
  - `fuzz_factor_test.sql` — a review's fuzz factor is checked to `[0, 1)` and inserted by its client, which cannot update it, with an update of the rating as control;
  - `public_decks_test.sql` — another user reads a public deck, its live cards and its owner's name, and no private or hidden deck; non-owners' writes are refused, with the owner's as control; the listing searches, sorts and leaves out blocked users' decks; copies are counted once per user, and never the owner's;
  - `deck_imports_test.sql` — a second copy by the same user adds nothing while another user's adds one, the owner's adds nothing, a count kept from before is added to, and clients reach no row;
  - `deck_reports_test.sql` — reports are insert-only by their reporter, once per deck, and the third distinct reporter hides the deck;
  - `deck_columns_test.sql` — the owner cannot write `hidden` or `import_count`, with an update of the writable columns as control; the publish and length checks; a `shared` card; the display name's length;
  - `uuid_keys_test.sql` — every synced id and every reference to one is `uuid` with no default, with `extraction_usage.id` as control; the five foreign keys are back; `list_public_decks` returns `uuid` ids and `record_deck_import` takes one, executable by `authenticated` and not `anon`; and a report takes the lock its deck's id took as text, with the third report's hide as control;
  - `checks_policies_test.sql` — each of the five checks refuses what it names, with an accepted row beside each as control, tombstones included, and all five are validated; `decks`, `cards` and `profiles` have one policy per command, the select policy testing the owner first, with an insert policy as the pattern's control;
  - `study_streak_test.sql` — on the instants `queue.test.ts` counts: the 04:00 boundary in UTC and in Seoul, a day across Los Angeles's change of offset at both ends, and a gap, each with a control; only the caller's live answers count; an unknown zone raises; and the function runs as the caller, stable, with an empty `search_path`, executable by `authenticated` and not `anon`;
  - `indexes_test.sql` — each index ADR 0034 names for a server query exists with its columns and predicate, and `cards_user_id_deck_id` is gone, with an index `cards` keeps as control;
  - `account_deletion_test.sql` — the tables in `public` are the ones it covers, every reference from `public` to `auth.users` cascades, and after a user is deleted no uuid column of any table holds its id, while the other user keeps its rows and its copy of the deleted user's deck.
- `make test` runs `supabase/test-db.sh`. Where Docker answers, it starts a throwaway stack of its own with only Postgres, which applies the migrations, runs the tests and prints their count ([ADR 0014](adr/0014-database-tests-on-a-stack-of-their-own.md)). Where Docker does not, it prints that the tests were skipped and why.
- The throwaway stack is named `smartman_test_<port>` and publishes its database on the first port in 54400–54499 that the run reserves under `${TMPDIR:-/tmp}/smartman-test-db/` and that nothing listens on. Concurrent runs, from several checkouts on one host, each get their own, and none touches the `smartman` stack or its rows.
- The script stops its stack, deleting its data, on every exit, interrupts included, and retries a stop that fails because another stack is stopping at the same moment. A stack it cannot stop fails the run, which prints how to remove it. A run killed with `SIGKILL` leaves its stack and reservation behind, to remove by hand.
- That reservation and that stop are defined once, in `supabase/test-stack.sh`, which `supabase/test-sync.sh` and `supabase/test-web.sh` source as well, so their stacks reserve under the same directory and stop the same way.
- CI's ubuntu job installs the Supabase CLI and runs them; the macOS runner has no Docker, so its log shows the skip.
- `make test` then runs `supabase/test-sync.sh`, the two-device sync test and the sharing server test against a throwaway stack with Auth and PostgREST ([`sync.md`](sync.md), [`sharing.md`](sharing.md)).

## Rationale

- [ADR 0010](adr/0010-server-schema-and-row-level-security.md) records the schema, the access rules and the revision mechanism.
- [ADR 0013](adr/0013-extract-cards-function-and-eval.md) records why the extraction count is a table written through one locked function.
- [ADR 0014](adr/0014-database-tests-on-a-stack-of-their-own.md) records why the tests run on a throwaway stack per run, superseding ADR 0010's "Tests" decision.
- [ADR 0015](adr/0015-sync-protocol-and-conflict-policy.md) records how sync pushes reviews within the column grant, and the two-device test's stack.
- [ADR 0026](adr/0026-delete-the-account-through-an-edge-function.md) records why an account is deleted through the admin API, so that the cascade removes its rows.
- [ADR 0020](adr/0020-public-decks-in-a-sharing-domain.md) records the public deck schema, the column grant on `decks`, and the replaced source check, which the owner approved pushing on 2026-10-15.
- [ADR 0034](adr/0034-key-synced-rows-by-client-made-uuids-purge-tombstones-past-a-revision-horizon-and-index-each-query.md) records the target data model, its measurements and the alternatives passed over, and the plan that builds it; issue #93 records the owner's direction.
- Issue #104 records the uuid conversion, issue #105 the checks and the merged select policies, issue #103 the streak function, and issue #113 the advisor lints read after #112.
- Issue #23 records the decisions made by the PM; issue #25 records those for the extraction count, issue #24 the fuzz factor column, issue #29 public decks, issue #67 counting each user's copy once, and issue #26 account deletion.

## Open questions

- None.
