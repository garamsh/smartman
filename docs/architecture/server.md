# Server

The Supabase schema the app syncs to, and the extraction count, the plans, and the admin area's role, audit log, functions, suspensions and removals from sharing beside it: its tables, row-level security, revisions, tombstones, account deletion, the migration of stored vocabulary backs to senses blocks, how migrations are named, how migrations and Edge Functions reach production, and the tests that hold them.

## Current decisions

### Location and migrations

- The schema is defined by migrations in `supabase/migrations/`, applied in order: by the Supabase CLI's `supabase db reset` locally ([ADR 0010](adr/0010-server-schema-and-row-level-security.md)), and by Supabase's GitHub integration on the remote project.
- `supabase/seed.sql` holds no rows; the tests insert their own.
- **Deploy path.** `main` is the deployed state. When a pull request adding a migration merges into `main`, Supabase's GitHub integration applies the migration to the production project; no one runs `supabase db push`. Its `Supabase Preview` check on the merge commit records the run.
  - Measured: #115's merge `9b98292d2f642e794e5d32d969e3999629c5964b` at 13:55:55Z on 2026-10-16, with `Supabase Preview` running 13:56:27–13:56:35Z; #118's merge `a940deaef30ca376e34cd83631bd4112055cda6a` at 15:41:51Z, with the check 15:42:24–15:42:33Z. A `supabase db push` minutes after #115's merge reported "Remote database is up to date" (issue #117).
  - To confirm a migration reached production: the `Supabase Preview` check succeeded on the merge commit, and `supabase migration list --linked` lists the migration's version in its remote column.
- **Gate.** A pull request whose migration changes or deletes existing data merges only after the owner approves it, since merging deploys it; the PM asks with the reviewed pull request in hand. An additive migration needs no such approval, but it is deployed as merged, so it must be correct then. Workers make no change to the remote project.
- **Order.** The integration applies every migration file that the production project's migration history lacks. A file older than the latest applied migration "still runs and the step finishes with a warning" (Supabase's GitHub integration guide, `supabase/supabase` commit `626f0d412a5f88ef260289d4ed2b787f9705d6fc`, committed 2026-10-14, read 2026-10-18). Such a file runs after migrations that sort after it, in an order no local `supabase db reset` follows.
- **Naming.** A new migration's version, the 14 digits its name starts with, is later than every migration on `main`. A contributor names it from the current UTC time, as `supabase migration new` does, when that is later. Otherwise the contributor uses the latest version on `main` plus one second ([ADR 0048](adr/0048-name-each-new-migration-after-every-migration-on-main-and-check-it-in-make-lint.md)).
  - `check-migration-order.sh`, run by `make lint`, fails when a migration file that `main` lacks has a version not later than the latest on `main`, or a name not starting with 14 digits. It reads `main` as the first parent of a pull request's merge commit in CI, where the ubuntu job's checkout fetches two commits deep, and as where `HEAD` left `origin/main` locally. It prints the number of new files and the base it compared with.
  - Branch protection on `main` requires branches to be up to date: `gh api repos/garamsh/smartman/branches/main/protection`, read 2026-10-18, returned `required_status_checks.strict: true` with the contexts `ci (ubuntu-latest)` and `ci (macos-latest)`, the CI jobs' names until #101 renamed them `ci (ubuntu)` and `ci (macos)`, which the PM sets as the required contexts when #101 merges. Of two pull requests that each pass the check against the same `main`, the second cannot merge until its branch is updated and the check runs again against the first.
  - `check-migration-order.test.sh`, run by `make test`, runs the check on repositories it builds in a temporary directory. It covers a merge commit cloned two commits deep, as CI checks one out, and a branch beside `origin/main`.

### Edge Function deploys

- **Deploy path.** When a pull request changing a function under `supabase/functions/` merges into `main`, Supabase's GitHub integration deploys it to the production project; no one runs `supabase functions deploy`. It deploys the functions `supabase/config.toml` declares under `[functions.<slug>]`, `extract-cards` and `delete-account`, and uploads one only when its bundle or its JWT verification setting changed. A function's bundle includes `supabase/functions/_shared/`, so a change there deploys both.
  - Source: Supabase's GitHub integration guide, `apps/docs/content/guides/deployment/branching/github-integration.mdx` in `supabase/supabase` at commit `626f0d412a5f88ef260289d4ed2b787f9705d6fc`, committed 2026-10-14, read 2026-10-18. Under "Deploying changes to production" it lists "Edge Functions declared in `config.toml` are deployed"; under "Edge Functions" it says "A function is uploaded again only when it changed."
  - Measured: #169's merge `5ab5440e4475237dc21f25911a4d9f52ab89c3a1` at 19:20:11Z on 2026-10-17 changed, under `supabase/`, only files in `supabase/functions/extract-cards/`. Its `Supabase Preview` check ran 19:20:38–19:20:47Z. On 2026-10-18, `supabase functions list` showed `extract-cards` at version 9, updated 19:20:46 UTC, and no one had deployed it by hand (issue #177).
  - To confirm a function reached production: the `Supabase Preview` check succeeded on the merge commit, and `supabase functions list` shows the function updated during that check.
- **Secrets.** The integration sets only the function secrets `config.toml` declares under `[edge_runtime.secrets]` (the same guide: "The step saves the function secrets declared under `[edge_runtime.secrets]`"), and `config.toml` declares none. The functions' secrets, `CARD_MODEL`, `OPENROUTER_API_KEY` and, where used, `CARD_RETRY_MODEL` ([`ai-extraction.md`](ai-extraction.md)), are set by hand on the production project by the owner or the PM; a merge changes none of them.
- **Gate.** A pull request changing a function merges only after the owner approves it when the change:
  - needs a secret the production project lacks, or a new value of one, which the owner or the PM sets before the merge, since the deploy the merge makes would otherwise run without it;
  - changes which model is called, or otherwise the cost of a call, since cost is the owner's.
  The PM asks with the reviewed pull request in hand. A prompt change on the same model ships as merged after the PM's review, with the eval as its evidence where one applies. A response the apps in use cannot read is not merged ([ADR 0051](adr/0051-extract-each-card-with-a-question-a-fullest-and-a-short-answer-and-a-detail-step-and-eval-notes-pages-by-terms.md)). Every other function change is deployed as merged, so it must be correct then. Workers make no change to the remote project.

### Tables

- `public` holds `decks`, `cards`, `reviews` and `card_states`, mirroring the app's local tables (`app/lib/database/database.dart`). Their ids are created on the device.
- `decks`, `cards` and `reviews` have `id` as primary key; `card_states` has `(user_id, card_id)`.
- Every synced id, and every column that references one, is `uuid`: `decks.id`, `cards.id`, `cards.deck_id`, `cards.origin_deck_id`, `reviews.id`, `reviews.card_id`, `card_states.card_id`, `deck_reports.deck_id` and `deck_imports.deck_id`. No id column has a default, so a row sent without an id is refused. `extraction_usage.id` is an identity ([ADR 0034](adr/0034-key-synced-rows-by-client-made-uuids-purge-tombstones-past-a-revision-horizon-and-index-each-query.md)).
- Migration `20261016180000_uuid_keys.sql` cast those columns from `text` in place, so every row kept its id. It first raises, changing nothing, unless every value is in canonical lowercase form, the only form Postgres returns unchanged, so the phone, which keeps ids as text, holds the same id the server returns ([`sync.md`](sync.md)). In one transaction it dropped the five foreign keys and the two policies that name those columns, cast them, and recreated the keys, the policies, `list_public_decks` and `record_deck_import`.
- PostgREST sends a uuid as the same JSON string a text id was, so app and web versions released before the conversion keep working.
- The app and the web create new ids as version 7; rows created before keep their version 4 ids, and nothing reads the version ([`sync.md`](sync.md)).
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
- A trigger hides a deck once three distinct users reported it, under an advisory lock on the deck seeded with 2, so concurrent reports are counted one after another. The lock's key hashes the deck's id as text, so the key a deck took before the ids were `uuid` is the key it takes now. An admin unhides it in the web admin area, which can also make a deck private and dismiss its reports (§Admin area).
- `public.user_blocks` holds a user's blocks; users select, insert and delete their own.
- `list_public_decks(search, sort, page_size, page_offset)` runs as the caller and lists visible public decks not of a user the caller blocked, whose name or description holds the search ignoring case, newest first or most copied first, with the owner's display name and live card count. It returns each deck's id as `uuid`.
- `record_deck_import(deck_id uuid)` runs as its owner: it returns false for a deck that is not visibly public, and otherwise true. A caller's first copy of a deck it does not own inserts a row in `public.deck_imports` and adds one to `import_count`; a later copy by that caller, or a copy by the owner, changes neither (issue #67).
- `public.deck_imports` holds one row per deck and user who copied it, keyed by the two, so concurrent copies by one user insert one row and add one between them. Clients hold no privilege on it, and row-level security is on with no policy. Removing a row, with its deck or its account, leaves `import_count` as it is.
- Copies made before `deck_imports` existed were not recorded per user, so their counts stay as they were and later copies add to them. Migration `20261016090000_deck_imports.sql` is additive: it creates the table and replaces the function with the same signature, changing no row.
- A deck is visibly public when it is public, not hidden and not deleted.

### Sync columns

- `updated_at` — the device's edit time, set by the client; #24 orders concurrent edits by it. `updated_at`, `created_at`, `reviewed_at` and `deleted_at` are the client's. The app's sync sends them at millisecond precision, as stored in schema v6, and so does the web.
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
- The app does not use the service role, and neither does the web: the admin area reads and writes through the functions of §Admin area with the user's session.

### Extraction usage

- `public.extraction_usage` holds one row per photo extraction the `extract-cards` function let through: an identity `id`, `user_id` referencing `auth.users` with `on delete cascade`, and `created_at` ([`ai-extraction.md`](ai-extraction.md), [ADR 0013](adr/0013-extract-cards-function-and-eval.md)).
- It is not synced: it has no revision, tombstone or edit time.
- `authenticated` may only select it, and row-level security allows only the caller's rows, so the app can read today's count. `anon` holds nothing.
- Rows are written only by `public.start_extraction(user_id)`, which the function calls (§Plans), and by `public.consume_extraction(user_id, daily_limit)`, which a function deployed before plans calls, both executable only by `service_role`. Each takes a transaction-level advisory lock on the user, counts the rows since the start of the UTC day, and inserts one under the limit; they share the lock and the rows, so a photo counts once whichever runs. `service_role` itself may not insert directly. A later change removes `consume_extraction` once nothing calls it.
- The lock's key is the hash of the user id seeded with 1, never the revision lock's seed 0.
- The migration adding it is additive: it creates the table, its index and the function, and changes nothing that existed.

### Admin area

- The admin role is the table `private.admins`, one row per admin with who granted it and when; a user without a row is not an admin ([ADR 0070](adr/0070-run-the-service-from-a-web-admin-area-whose-role-and-audit-log-live-in-the-database-and-whose-every-read-and-write-is-checked-there.md)). It sits in `private`, which the API does not expose, and no client role holds a privilege on it, so no email, id or list in code or configuration names an admin.
- The first admin is a row the PM inserts on the production project after the migration deploys: `insert into private.admins (user_id) select id from auth.users where email = 'sauce@garam.sh';`. Every later grant and revoke goes through the admin area.
- `private.admin_audit` records every admin write: the admin's id, set null when that account is deleted so the row stays, and a snapshot of the email, a snake-case `action` and `target_kind`, a `target_id`, a JSON `detail` object and the time. The writing function names the action; a later one adds its own names with no schema change.
- Every admin read and write is a `security definer` function in `public` with an empty `search_path`, executable by `authenticated` and not `anon`. Each first calls `private.require_admin()`, which raises `42501` unless the caller has a row in `private.admins`, and each write records itself through `private.audit()` in its transaction. A write that changes nothing records nothing. `public.is_admin()` answers the caller's role.
- The functions: `admin_overview` and `admin_extractions_by_day` (users, study and extractions per UTC day); `admin_reported_decks`, `admin_public_decks`, `admin_deck` and `admin_deck_cards` (a deck is readable only when public or reported); `admin_find_users` and `admin_user`; `admin_admins` and `admin_audit_log`; and the writes `admin_set_deck_hidden`, `admin_unpublish_deck`, which sets the deck private with an edit time of now so the owner's devices pull it, `admin_dismiss_reports`, which leaves a hidden deck hidden, `admin_grant_admin` by an existing user's email, and `admin_revoke_admin`, which refuses the caller's own role and runs one at a time under an advisory lock seeded with 3, checking the caller's role again once the lock is held, so two admins revoking each other at once cannot leave none.
- The overview's counts across users scan the live reviews in range and `extraction_usage` without an index of their own; the PM adds one when `supabase inspect db outliers` lists either function among the ten statements of highest total time.
- Migration `20261019120000_admin.sql` is additive: it creates the two tables, their indexes and the functions, and changes no existing row or object.

### Plans

- `private.plans` holds the three plans, `free`, `pro` and `special`, each with its `model`, an OpenRouter id checked to the form `vendor/model`, its `daily_limit` from 0 to 1000, and who last changed it and when ([ADR 0071](adr/0071-give-each-user-a-plan-whose-model-and-daily-limit-an-admin-sets-in-the-database-and-make-one-model-call-per-photo.md)). Migration `20261019180000_plans.sql` seeds all three on `anthropic/claude-haiku-5.5` and 30 a day, as data the admin area edits.
- `private.user_plans` holds a user's grant of `pro` or `special`, with an optional end that only Special may have, and who granted it and when. A user without a row is on Free, and so is one whose Special has ended; `private.plan_of(user_id)` answers which plan a user is on.
- Both sit in `private`, and no client role holds a privilege on them.
- `public.start_extraction(user_id)`, executable only by `service_role`, returns the user's plan, its model and limit, and whether the photo is allowed, recording it when it is, under the extraction lock (§Extraction usage). With the plan's settings missing it returns no row, which the function answers as not configured.
- The admin functions, each checking the role and recording itself as §Admin area states: `admin_plans` and `admin_set_plan` (recorded as `set_plan` on a `plan`, with the settings before and after); `admin_user_plan`; `admin_grant_plan`, which replaces any earlier grant and refuses an end on Pro or one not in the future, and `admin_revoke_plan` (recorded as `grant_plan` and `revoke_plan` on a `user`, with the user's email).
- The migration is additive: it creates the two tables with their seed rows, their indexes and the functions, and changes no existing row or object.

### Suspension and removal from sharing

- `private.suspensions` holds each suspended user with the reason, who suspended and when; a user without a row is active ([ADR 0072](adr/0072-suspend-a-user-through-supabase-auth-s-ban-and-restrictive-write-policies-remove-a-public-deck-from-sharing-for-good-and-read-any-deck-in-the-admin-area.md)). `private.deck_removals` holds each deck removed from sharing for good, with the reason, who removed it and when. No client role holds a privilege on either.
- `admin_suspend_user` sets the user's `auth.users.banned_until` 100 years ahead, and `admin_unsuspend_user` sets it to null, so Supabase Auth refuses a suspended user's sign-in and refresh with `user_banned`. This is the only write to the `auth` schema in any admin function: none writes an email, a password, a phone, a metadata column or a `profiles` row.
- Restrictive policies on `decks`, `cards`, `reviews` and `card_states`, one per command a user may run, refuse a suspended user's writes through `public.is_suspended()`; the owner policies are unchanged, and reads still pass. `extract-cards` asks `public.user_suspended(user_id)`, executable only by `service_role`, before it counts a photo ([`ai-extraction.md`](ai-extraction.md)).
- `admin_remove_deck` makes a deck private with an edit time of now, as `admin_unpublish_deck` does, and records its removal; restrictive policies on `decks` keep a removed deck from being made public again, through `public.deck_removed_from_sharing(deck_id)`.
- The admin functions, each checking the role and recording itself as §Admin area states: `admin_search_users`, a page of the users whose email holds the query, those starting with it first, with whether each is suspended and the total; `admin_user_suspension`; `admin_suspend_user` (recorded as `suspend_user` on a `user`, with the email and the reason), which refuses the caller, an unknown user and a suspended one; `admin_unsuspend_user` (`unsuspend_user`); `admin_user_decks`, a user's live decks, private ones too; `admin_user_deck` and `admin_user_deck_cards`, any deck read-only with its removal; and `admin_remove_deck` (`remove_deck` on a `deck`, with the name and the reason).
- `admin_deck`, `admin_deck_cards` and `admin_find_users` stay in the database with no caller; dropping them is a non-additive change left to a migration the PM approves.
- Migration `20261019200000_admin_users.sql` creates the two tables, their indexes, the policies and the functions, and changes no existing row and replaces no existing object.

### Account deletion

- The `delete-account` Edge Function deletes the caller's user from `auth.users` through Supabase Auth's admin API, with the service-role key, which stays in the function ([`account.md`](account.md), [ADR 0026](adr/0026-delete-the-account-through-an-edge-function.md)). The deletion is hard, so the cascade runs.
- Every table in `public` deletes with the user: `decks`, `cards`, `reviews`, `card_states`, `extraction_usage` and `profiles` by `user_id`, `deck_reports` and `deck_imports` by their user and by their deck, and `user_blocks` by either side. In `private`, `admins`, `user_plans` and `suspensions` delete with their user and `deck_removals` with its deck, and a granter or editor column, `admins.granted_by`, `user_plans.granted_by`, `plans.updated_by`, `suspensions.suspended_by` or `deck_removals.removed_by`, is set null; `admin_audit` keeps the admin's rows with `admin_id` set null. Another user's copy of a deleted user's deck stays theirs.
- A new table holding a user id references `auth.users` with `on delete cascade`, except a column naming who granted or edited a row, which is set null so the row outlives that admin, and `private.admin_audit`, whose rows outlive the admin who wrote them ([ADR 0070](adr/0070-run-the-service-from-a-web-admin-area-whose-role-and-audit-log-live-in-the-database-and-whose-every-read-and-write-is-checked-there.md)).
- Merging the pull request that adds or changes the function deploys it (§Edge Function deploys).

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

### Horizon and watermark

- `private.sync_horizon` holds one row: the revision the last tombstone purge purged below, 0 until a purge runs ([ADR 0034](adr/0034-key-synced-rows-by-client-made-uuids-purge-tombstones-past-a-revision-horizon-and-index-each-query.md) §3).
- `public.sync_horizon()` returns one row to the caller: `horizon`, that revision, and `watermark`, the last value of `private.revision` read after taking the caller's revision lock, the advisory lock the revision trigger takes ([ADR 0041](adr/0041-raise-each-pull-cursor-to-a-watermark-read-under-the-user-s-lock-and-strip-local-tombstones-in-place.md)).
  - Each of the caller's writes draws its revision under that lock and holds it to commit, so every revision of the caller's rows at or below the watermark is committed when it is read, and every later one is above it. A sync run reads it before pulling and raises each completed table's cursor to it ([`sync.md`](sync.md)).
  - It is `security definer`, `volatile`, since it takes a lock, and sets `search_path = ''`. `execute` is revoked from `public` and `anon` and granted to `authenticated`.
- Migration `20261017120000_sync_horizon.sql` added the table, holding 0, and the function, changing no row.

### Tombstone purge

- A `pg_cron` job, `purge-tombstones`, runs `private.purge_tombstones()` daily at 18:00 GMT, 03:00 in Korea ([ADR 0034](adr/0034-key-synced-rows-by-client-made-uuids-purge-tombstones-past-a-revision-horizon-and-index-each-query.md) §3). Each run:
  - records the revision sequence's last value in `private.revision_marks`, with the server's time;
  - deletes `cron.job_run_details` rows that ended more than 30 days earlier;
  - purges the `decks`, `cards` and `card_states` tombstones whose `revision` is at or below the latest mark taken 90 days or more earlier, and stores that mark as the horizon in `private.sync_horizon`, which `sync_horizon()` returns ([`sync.md`](sync.md));
  - deletes the marks older than that one.
  - With no mark 90 days old, a run purges nothing and the horizon stays where it is. The first purge therefore comes 90 days after the first mark.
- Study history survives deletion (the owner's decision, issue #93):
  - a card tombstone that no review references is deleted, with its card state;
  - one that reviews reference keeps its row, stripped: `front` and `back` become `[]` and `card_key` `''`, so its reviews stay in the streak and the statistics;
  - every card state tombstone is deleted;
  - a deck tombstone is deleted once no card row references it, with its reports and its users' copy records, which cascade from it. Until then it keeps its row, stripped of its name and description and made private.
  - A strip is an update, so the row takes a new revision and devices pull it. A row already stripped is not updated again.
  - Only account deletion removes reviews and the kept rows.
- A run that purges first locks `cards` and `reviews` in `share row exclusive` mode until it commits. A write to either waits, so no review or card written during the run comes to reference a tombstone the run deletes ([ADR 0053](adr/0053-purge-tombstones-before-any-store-release-enable-pg-cron-in-the-purge-s-migration-and-lock-cards-and-reviews-while-it-purges.md)). A run with no mark 90 days old takes no lock.
- `private.purge_tombstones()` runs as its owner and sets `search_path = ''`; `execute` is revoked from `public`, `anon` and `authenticated`.
- Migration `20261018090002_tombstone_purge.sql` added the marks table, the function and the job. It deletes no row itself.
  - It first calls `private.check_purge_start()`, which raises, changing nothing, unless `pg_cron` is in `pg_available_extensions` and `shared_preload_libraries`, `private.sync_horizon` holds its one row at 0, and no job named `purge-tombstones` exists. The function stays, so its refusals are tested.
  - It then runs `create extension if not exists pg_cron with schema pg_catalog`. **Merging it enables `pg_cron` in production if it is not on yet**; where the owner enabled Cron first, the statement does nothing.
- **Order.** The purge was built before any store release, by the owner's decision of 2026-10-18 in issue #108, which supersedes ADR 0034 §9's order of building it after the app's store release ([ADR 0053](adr/0053-purge-tombstones-before-any-store-release-enable-pg-cron-in-the-purge-s-migration-and-lock-cards-and-reviews-while-it-purges.md)). The only client devices then were the owner's, running `main`'s build, which reads the watermark.
- **Runs.** `cron.job_run_details` records each run, so a failure or a missing day shows there; a horizon that stops rising shows through `sync_horizon()`.

### Senses migration

- Migration `20261019180003_senses_migration.sql` turns each live card whose back is one text block of sense lines, such as `[명] 사과`, into a back of one `senses` block ([`deck.md`](deck.md), [ADR 0075](adr/0075-store-a-vocabulary-card-s-senses-as-a-typed-block-and-show-each-label-in-brackets-before-its-meaning.md), #228). It changes existing data; the owner approved it for the 105 cards the dry run found on production, and #255's dry run merges before it.
- The rules are functions in `private`, which the dry run (`supabase/senses-dry-run.sql`) calls too: `sense_labels` holds the labels and the part of speech each names, `sense_forms` the four forms and their order, `sense_line` a line's first matching form, and `senses_block` the block a back becomes, or null when it does not convert.
- `private.migrate_senses()` converts, and the migration calls it once.
  - It locks each card it converts and first copies the card's back into `private.senses_migration_backup` (`card_id`, `back`, `migrated_at`). That table enables row-level security with no policy and grants nothing to `anon` or `authenticated`, so no client reads it. A row goes with its card's delete.
  - A second run converts nothing, since a senses block is no text block, and a backed-up card keeps its first backup.
- **How it reaches devices.** The update draws a new `revision` through the trigger, so every device pulls the card. The card keeps its `updated_at`:
  - a device holding the card synced takes the server's copy on the tie;
  - a device with an edit not yet pushed holds a later `updated_at`, so its edit wins the merge and is pushed over the migration's ([`sync.md`](sync.md) §Conflicts).
  - No front, card key, review or card state changes.
- **Revert.** `select private.revert_senses_migration();`, run by the PM against production, restores each backed-up back on a live card that still holds the block the migration wrote, and returns how many. A card edited since keeps its edit. It also draws new revisions and keeps `updated_at`.
- Every function revokes `execute` from `public`, `anon` and `authenticated`, and runs as `security invoker`: only the migration and the PM call them.

### Target data model (not built yet)

[ADR 0034](adr/0034-key-synced-rows-by-client-made-uuids-purge-tombstones-past-a-revision-horizon-and-index-each-query.md) decides the schema below. None of it is built yet: each bullet holds once the migration that its implementation issue adds has been applied. Until then the decisions above describe the database.

- **Functions** run as `security invoker` unless they must reach what the caller cannot. Each `security definer` function sets `search_path = ''` and revokes `execute` from `public`. The definer functions are the revision trigger, `consume_extraction`, `hide_reported_deck`, `record_deck_import`, `sync_horizon` and the purge.
- **Public listing.** Search stays a scan, matching `strpos` on `lower()`, until a threshold in ADR 0034 is crossed; then a `pg_trgm` GIN index on the visibly public decks serves it. The card count stays a correlated count.
- **Watching.** After each applied migration, the PM reads Supabase's Security and Performance Advisors, and monthly reads `supabase inspect db outliers` and `index-stats`. Each lint is fixed or recorded in an issue.

### Study day start

- `public.study_day_start_hour()` returns 4, the hour a study day starts at in local time, `studyDayStartHour` of `app/lib/study/src/queue.dart` and `web/src/features/study/queue.ts`. `study_streak_before`, `study_days_before` and `study_record_days` start each study day there, so the server holds the hour once (issue #220).
- `web/src/features/study/__tests__/rules.test.ts` fails when the hour the latest migration defining the function returns differs from `queue.ts`'s, and `study_day_start_test.sql` when one of the three functions does not follow a change of it.
- It is `immutable`, `security invoker`, and sets `search_path = ''`. `execute` is revoked from `public` and `anon` and granted to `authenticated`, which calls the three functions.
- Migration `20261019180001_study_day_start.sql` added it and replaced the three functions with the same results, changing no row.

### Streak

- `public.study_streak_before(time_zone, before)` returns how many study days in a row before the one holding `before` hold one of the caller's live answers, with days from 04:00 to 04:00 in the zone named, as `web/src/features/study/queue.ts` counts them, starting at `study_day_start_hour()` ([ADR 0034](adr/0034-key-synced-rows-by-client-made-uuids-purge-tombstones-past-a-revision-horizon-and-index-each-query.md) §4). The web's `readToday` calls it ([`web.md`](web.md)).
- It walks back one day at a time from local 04:00 to local 04:00, so a day across a change of offset keeps both ends, and stops at the first day without an answer. Each day is one backward probe of `reviews_live_user_id_reviewed_at` for its latest answer.
- It is `security invoker`, so row-level security decides what it reads, `stable`, and sets `search_path = ''`. `execute` is revoked from `public` and `anon` and granted to `authenticated`. A zone Postgres does not know raises `22023`.
- Migration `20261017090000_study_streak.sql` added it, changing no row.

### Study days

- `public.study_days_before(time_zone, before, days, cap_ms)` returns the caller's latest `days` study days before `before`, oldest first, each from 04:00 to 04:00 in the zone named, as `web/src/features/study/queue.ts` counts them, starting at `study_day_start_hour()`: its start, and the time and number of the answers that were not their card's first live answer and of those that were, each answer counted up to `cap_ms` ([ADR 0043](adr/0043-set-each-day-s-new-cards-from-the-user-s-recency-weighted-study-time-and-pace-and-count-an-answer-s-time-only-in-the-foreground.md)). The web's `readToday` calls it with 30 days and 30 s ([`web.md`](web.md)).
- A day without a live answer is no study day, so it is neither returned nor counted. The function walks back one study day at a time, each step one backward probe of `reviews_live_user_id_reviewed_at`, then reads the window's answers through the same index; whether an answer is its card's first is one probe of `reviews_user_id_card_id`.
- It is `security invoker`, `stable`, and sets `search_path = ''`. `execute` is revoked from `public` and `anon` and granted to `authenticated`. A zone Postgres does not know raises `22023`.
- Migration `20261018090000_study_days.sql` added it, changing no row.

### Record

- `public.study_record_days(time_zone, before)` returns one row per study day before `before` holding one of the caller's live answers, oldest first, each from 04:00 to 04:00 in the zone named, starting at `study_day_start_hour()`: its start, the distinct cards answered, its scheduled reviews and those answered "good" ([ADR 0037](adr/0037-define-the-record-tab-s-retention-recall-bands-mastered-weeks-and-study-days-and-compute-them-on-the-device.md), [ADR 0047](adr/0047-read-the-web-record-through-two-server-functions-and-fold-it-through-the-engine-on-the-server.md)). A review is scheduled when it is its card's first answer of the day and the card has an answer on an earlier day. Every live answer counts, whether or not its card is live. It reads the caller's answers through `reviews_live_user_id_reviewed_at`.
- `public.study_record_cards()` returns one row per live card of a live deck of the caller's with a live answer: its live state or nulls, and its live answers' ratings, times and fuzz factors, oldest first. A card's answers are read through `reviews_user_id_card_id`; the cards are the whole library, as the web's library read scans them.
- Both are `security invoker`, `stable`, and set `search_path = ''`. `execute` is revoked from `public` and `anon` and granted to `authenticated`. A zone Postgres does not know raises `22023`. The web's `/record` page calls both ([`web.md`](web.md)).
- Migration `20261018090001_study_record.sql` added them, changing no row.

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
  - `admin_test.sql` — every admin function refuses a signed-in user who is not an admin and refuses `anon`, with an admin as control; no client reads or writes the role or the log directly; the overview, the extractions by UTC day, the reported and public decks, a deck readable only while public or reported, the user search and a user's counts; hiding, unhiding, unpublishing with a new revision and edit time, and dismissing, each recorded once and a no-op not at all; granting by email, refusing one's own revoke, a revoke taking the admins lock, against none held before, a revoked admin refused at once, the audit log newest first with its paging, and a deleted admin's rows kept by email with no admin id;
  - `plans_test.sql` — the three plans seeded on Haiku 5.5 at 30; every admin plan function refusing a non-admin and `anon`, with an admin as control, and no client reading or writing the plans or the grants or starting an extraction; a user resolved to Free, Pro, an unended Special and an ended Special as Free, each served by its plan's model; photos counted against each plan's limit with only allowed ones recorded, and `consume_extraction` counting the same rows; no plan without Free's settings; setting a plan, a no-op, and a malformed model or a limit over 1000 refused; granting, replacing, the refused grants and revoking, each recorded once; and a deleted user's grant gone while a deleted admin's grants and settings stay;
  - `admin_users_test.sql` — every function of §Suspension and removal from sharing refusing a non-admin and `anon`, with an admin as control; a suspended user's inserts, updates and deletes refused on the four synced tables while its reads pass, against an active user's writes; the ban set and cleared; suspending oneself, an unknown user and a suspended one refused; a user's decks and any deck read; a removed deck made private and its owner's republish refused, against another deck's publish; the search's order and paging; each write recorded once; and every user's email, password hash, phone, metadata and profile unchanged after every admin write, with no function updating an `auth.users` column but `banned_until`;
  - `deck_imports_test.sql` — a second copy by the same user adds nothing while another user's adds one, the owner's adds nothing, a count kept from before is added to, and clients reach no row;
  - `deck_reports_test.sql` — reports are insert-only by their reporter, once per deck, and the third distinct reporter hides the deck;
  - `deck_columns_test.sql` — the owner cannot write `hidden` or `import_count`, with an update of the writable columns as control; the publish and length checks; a `shared` card; the display name's length;
  - `uuid_keys_test.sql` — every synced id and every reference to one is `uuid` with no default, with `extraction_usage.id` as control; the five foreign keys are back; `list_public_decks` returns `uuid` ids and `record_deck_import` takes one, executable by `authenticated` and not `anon`; and a report takes the lock its deck's id took as text, with the third report's hide as control;
  - `checks_policies_test.sql` — each of the five checks refuses what it names, with an accepted row beside each as control, tombstones included, and all five are validated; `decks`, `cards` and `profiles` have one permissive policy per command, the select policy testing the owner first, with an insert policy as the pattern's control;
  - `tombstone_purge_test.sql` — a run with no mark 90 days old purges nothing, keeps the horizon at 0, takes a mark, takes no lock and trims the run details past 30 days, with those within kept as control; a run past the 91-day mark raises the horizon to it, not to the 89-day one, strips a studied card's tombstone with its review kept and a new revision, deletes an unstudied one and every card state tombstone, deletes a deck tombstone left without cards and strips one holding a stripped card, and locks `cards` and `reviews`, with live rows and a tombstone above the horizon untouched as controls; the job's schedule; the function's owner rights and privileges; and the migration's guard passing with the horizon at 0 and no job, as control, and refusing a stored horizon, a missing horizon row and an existing job;
  - `sync_horizon_test.sql` — the horizon is 0 until one is stored and then the stored one; the watermark is the sequence's last value, at or above the caller's latest row and below a row written after the call; the call takes the caller's revision lock, with another user's lock before its call as control; and the function runs as its owner, volatile, with an empty `search_path`, executable by `authenticated` and not `anon`;
  - `study_days_test.sql` — the study days before a time, oldest first, rests left out, a review and a first answer apart with a deleted earlier answer read for nothing, a 10-minute answer counted at the cap with a higher cap as control, only the latest so many study days with history before them changing nothing and a longer window reading it as control, the 04:00 boundary in Seoul, answers at or after the time left out, only the caller's answers; an unknown zone raises; and the function runs as the caller, stable, with an empty `search_path`, executable by `authenticated` and not `anon`;
  - `study_record_test.sql` — on the histories `app/test/study/stats_test.dart` counts: a card's first answer of a later study day scheduled from 04:00, its first answer ever, a re-show and a second answer the same day not, a deleted answer and answers at or after the time left out, the 04:00 boundary in Seoul with each card counted once a day and UTC as control, only the caller's answers, an unknown zone raising; each live card of a live deck with an answer, its state or none and its live answers in order with their fuzz factors, with a deleted card, a card of a deleted deck, a card with no answer and a deleted state each restored or added as control; and both functions run as the caller, stable, with an empty `search_path`, executable by `authenticated` and not `anon`;
  - `study_day_start_test.sql` — the hour is 4; an answer at 04:30 counted in its day from 04:00 by the streak, the study days and the record, and, with the hour moved to 5 in the test's transaction, in the day from 05:00 the day before by all three; executable by `authenticated` and not `anon`;
  - `study_streak_test.sql` — on the instants `queue.test.ts` counts: the 04:00 boundary in UTC and in Seoul, a day across Los Angeles's change of offset at both ends, and a gap, each with a control; only the caller's live answers count; an unknown zone raises; and the function runs as the caller, stable, with an empty `search_path`, executable by `authenticated` and not `anon`;
  - `indexes_test.sql` — each index ADR 0034 names for a server query exists with its columns and predicate, and `cards_user_id_deck_id` is gone, with an index `cards` keeps as control;
  - `senses_migration_test.sql` — on the dry run's fixture: each form's line rule and a label off the list or a label without a meaning refused; the six cards of the recognised forms converted, a sense per line with its label and category, and the mixed card, the note, the back of two blocks, the deleted card and the unrecognised label untouched; each original back in the backup; no front, card key, edit time, review or card state changed while each converted card's revision rose; a second run changing nothing; and the revert restoring every back but one edited since;
  - `account_deletion_test.sql` — the tables in `public` are the ones it covers, every reference from `public` to `auth.users` cascades, and after a user is deleted no uuid column of any table holds its id, while the other user keeps its rows and its copy of the deleted user's deck.
- `make test` runs `supabase/test-db.sh`. Where Docker answers, it starts a throwaway stack of its own with only Postgres, which applies the migrations, runs the tests and prints their count ([ADR 0014](adr/0014-database-tests-on-a-stack-of-their-own.md)). Where Docker does not, it prints that the tests were skipped and why.
- The throwaway stack is named `smartman_test_<port>` and publishes its database on the first port in 54400–54499 that the run reserves under `${TMPDIR:-/tmp}/smartman-test-db/` and that nothing listens on. Concurrent runs, from several checkouts on one host, each get their own, and none touches the `smartman` stack or its rows.
- The script stops its stack, deleting its data, on every exit, interrupts included, and retries a stop that fails because another stack is stopping at the same moment. A stack it cannot stop fails the run, which prints how to remove it. A run killed with `SIGKILL` leaves its stack and reservation behind, to remove by hand.
- That reservation and that stop are defined once, in `supabase/test-stack.sh`, which `supabase/test-sync.sh` and `supabase/test-web.sh` source as well, so their stacks reserve under the same directory and stop the same way.
- CI's ubuntu job installs the Supabase CLI and runs them.
- `make test` then runs `supabase/test-sync.sh`, the two-device sync test, the sharing server test and the suspension test against a throwaway stack with Auth and PostgREST ([`sync.md`](sync.md), [`sharing.md`](sharing.md), [`account.md`](account.md)).

## Rationale

- [ADR 0010](adr/0010-server-schema-and-row-level-security.md) records the schema, the access rules and the revision mechanism.
- [ADR 0013](adr/0013-extract-cards-function-and-eval.md) records why the extraction count is a table written through one locked function.
- [ADR 0014](adr/0014-database-tests-on-a-stack-of-their-own.md) records why the tests run on a throwaway stack per run, superseding ADR 0010's "Tests" decision.
- [ADR 0015](adr/0015-sync-protocol-and-conflict-policy.md) records how sync pushes reviews within the column grant, and the two-device test's stack.
- [ADR 0026](adr/0026-delete-the-account-through-an-edge-function.md) records why an account is deleted through the admin API, so that the cascade removes its rows.
- [ADR 0020](adr/0020-public-decks-in-a-sharing-domain.md) records the public deck schema, the column grant on `decks`, and the replaced source check, which the owner approved pushing on 2026-10-15.
- [ADR 0034](adr/0034-key-synced-rows-by-client-made-uuids-purge-tombstones-past-a-revision-horizon-and-index-each-query.md) records the target data model, its measurements and the alternatives passed over, and the plan that builds it; issue #93 records the owner's direction.
- [ADR 0041](adr/0041-raise-each-pull-cursor-to-a-watermark-read-under-the-user-s-lock-and-strip-local-tombstones-in-place.md) records why `sync_horizon()` returns a watermark read under the caller's lock beside the horizon.
- [ADR 0043](adr/0043-set-each-day-s-new-cards-from-the-user-s-recency-weighted-study-time-and-pace-and-count-an-answer-s-time-only-in-the-foreground.md) records why the web reads a day's study days through `study_days_before`.
- [ADR 0047](adr/0047-read-the-web-record-through-two-server-functions-and-fold-it-through-the-engine-on-the-server.md) records why the web's 기록 reads through `study_record_days` and `study_record_cards`, and folds the cards through the engine on the server.
- [ADR 0053](adr/0053-purge-tombstones-before-any-store-release-enable-pg-cron-in-the-purge-s-migration-and-lock-cards-and-reviews-while-it-purges.md) records why the purge was built before any store release, why its migration enables `pg_cron`, and why a run locks `cards` and `reviews`; issue #108 records the owner's decision.
- [ADR 0070](adr/0070-run-the-service-from-a-web-admin-area-whose-role-and-audit-log-live-in-the-database-and-whose-every-read-and-write-is-checked-there.md) records why the admin role and the audit log are tables in `private`, why every admin read and write is a function that checks the role, and why the web needs no service-role key; issue #223 records the owner's request and the PM's scope, and #224 what builds on it.
- [ADR 0072](adr/0072-suspend-a-user-through-supabase-auth-s-ban-and-restrictive-write-policies-remove-a-public-deck-from-sharing-for-good-and-read-any-deck-in-the-admin-area.md) records why a suspension is Supabase Auth's ban set by a role-checked function, with restrictive write policies and a check in `extract-cards`, why a deck removed from sharing stays private, and why the admin area reads any deck; issue #234 records the owner's request and the PM's scope.
- [ADR 0048](adr/0048-name-each-new-migration-after-every-migration-on-main-and-check-it-in-make-lint.md) records how the integration treats an older migration, with its source, and why a new migration is named after every one on `main`; issue #149 records the finding.
- Issue #104 records the uuid conversion, issue #105 the checks and the merged select policies, issue #103 the streak function, issue #106 the horizon and the watermark, issue #107 the web's version 7 ids, and issue #113 the advisor lints read after #112.
- Issue #177 records that merging deployed `extract-cards`, with its timestamps; the PM decided the function gate in the dispatch of #177 on 2026-10-18.
- Issue #23 records the decisions made by the PM; issue #25 records those for the extraction count, issue #24 the fuzz factor column, issue #29 public decks, issue #67 counting each user's copy once, and issue #26 account deletion.

## Open questions

- None.
