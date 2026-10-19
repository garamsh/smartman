# ADR 0010: Sync to a per-user Supabase schema guarded by row-level security, with server-set revisions and pgTAP tests in `make test`

> Status: accepted; its "Tests" decision superseded by ADR-0014; the `deleted_at` tombstone on `reviews` and `card_states` superseded by ADR-0077
> Date: 2026-10-15

Append-only: once merged, the body below is not rewritten. A fact later found wrong is corrected in an appended note, not edited out; a revised decision is a new ADR that supersedes this one.

## Context

- Issue #23 (M5a) adds the server side of sync; #24 builds the client sync on it. The PM decided there:
  - tables `decks`, `cards`, `reviews` and `card_states` in `public`, mirroring the local ones with the same text ids; `decks`, `cards` and `reviews` carry `user_id` referencing `auth.users` with `on delete cascade`, `card_states` is keyed by `(user_id, card_id)`, and card content is `jsonb`;
  - on every table `updated_at` set by the client, `deleted_at` as a tombstone, and `revision` set by a trigger from one global sequence on every insert and update, which a client cannot set;
  - row-level security on every table, allowing select, insert, update and delete only where `user_id = auth.uid()`; no `anon` access, and no service role in the app;
  - a card's deck, and a review's or card state's card, belong to the same user; reviews are insert-only for clients except their rating;
  - migrations in `supabase/migrations/`; pgTAP tests in `supabase/tests/` run by `supabase test db`, by the ubuntu CI job, and skipped with the reason where there is no Docker;
  - the PM pushes the migration to the remote project after merge.
- Asked during implementation, the PM confirmed that `authenticated` gets only `select`, `insert` and `update (rating, updated_at)` on `reviews`: no client delete and no client tombstone, the four policies kept on every table, and a review removed only through the `auth.users` cascade.
- A sequence value is drawn when a row is written, not when its transaction commits. Without more, two transactions of one user can commit in the opposite order to their revisions, and a pull that has advanced its cursor past the later revision never sees the earlier one. The PM's review of PR #32 required revisions to follow commit order per user, by a per-user advisory transaction lock or an equally correct alternative.
- An `xid8` commit watermark keeps one user's writes concurrent, but every pull would then compare transaction ids against the oldest transaction still running, logic that #24's query would carry. A lock keeps the pull a plain comparison, at the cost of one user's writes waiting for each other.
- Supabase's local stack grants `anon` and `authenticated` every privilege on new tables in `public` by default privileges (`auto_expose_new_tables` in `supabase/config.toml`, left unset, which the file's comment says falls back to `true`).
- Supabase CLI 2.120.0's `supabase test db` runs `pg_prove` over every file under `supabase/tests/`, recursively, and creates the `pgtap` extension itself. `supabase start` with `--exclude` for every other service starts only Postgres.
- `supabase/setup-cli` v3.0.1 (commit `45a513f8c64c0bc8e0e3dfe572b5c95be85f6359`) installs a fixed CLI version from npm.

## Decision

- **Schema.** One migration creates the four tables with the columns and keys the issue names; `user_id` defaults to `auth.uid()`, and a card side must be a `jsonb` array.
- **Revision.** The sequence `private.revision` and the trigger function `private.set_revision`, which overwrites `revision` on every insert and update of the four tables, live in the schema `private`, which the API does not expose. Before drawing, it takes `pg_advisory_xact_lock` on a 64-bit hash of the row's `user_id`, held until commit, so one user's writing transactions serialize and each later commit holds a higher revision. The function is `security definer`, so clients hold no privilege on the sequence.
- **Access.** The migration revokes every privilege from `anon` and `authenticated` on the four tables and grants back what clients need; `reviews` gets `select`, `insert` and `update (rating, updated_at)`. One policy per command per table allows only the caller's rows.
- **Integrity.** Composite foreign keys, `(user_id, deck_id)` to `decks (user_id, id)` and `(user_id, card_id)` to `cards (user_id, id)`, rather than a check trigger.
- **Tests.** `supabase/test-db.sh`, run by `make test`, skips with the reason where Docker does not answer. Otherwise it starts the local stack with only Postgres if none is running, runs `supabase db reset`, runs `supabase test db`, prints the count, and stops the stack it started. CI's ubuntu job installs CLI 2.120.0 with `supabase/setup-cli`, pinned by commit.

## Consequences

- Isolation does not depend on the project's default privileges or on the app's queries: a request through the API with the publishable key reaches only the signed-in user's rows.
- A client sends rows as they are and the server stamps them; #24 pulls each table by `revision` and never computes one, and a cursor cannot pass a row of the same user that commits later.
- One user's concurrent writes wait for each other until commit; different users' do not, except when their ids' hashes collide.
- Composite foreign keys make a cross-user reference fail as any foreign-key violation does, and need the extra `unique (user_id, id)` on `decks` and `cards`.
- Changing which columns of a review a client may update is a migration, as is any later table.
- `make test` resets the local database when a stack is already running, so local rows do not survive it.
- The Supabase CLI release is stated in `README.md` and in `.github/workflows/ci.yml`; no bot proposes its bump.

## Signs the decision was wrong

- #24 needs a server-side operation a row-level policy cannot express, such as merging two devices' edits, and moves it into a function that bypasses the policies.
- One user's writes queue behind a long transaction, from a bulk import or a slow client, long enough to time out.
- A pull misses a row anyway, which would mean a write path that skips the trigger.
- A review needs a correction other than its rating, or a client-side tombstone, and the column grant has to widen.
- The skip on hosts without Docker hides a broken migration until CI's ubuntu job catches it.
