# ADR 0048: Name each new migration after every migration on main, and check it in make lint

> Status: accepted
> Date: 2026-10-18

Append-only: once merged, the body below is not rewritten. A fact later found wrong is corrected in an appended note, not edited out; a revised decision is a new ADR that supersedes this one.

## Context

- Merging a migration into `main` deploys it: Supabase's GitHub integration applies it to the production project (`server.md`, Deploy path).
- Supabase's documentation of the integration, read on 2026-10-18 at commit `626f0d412a5f88ef260289d4ed2b787f9705d6fc` of `supabase/supabase` (`apps/docs/content/guides/deployment/branching/github-integration.mdx`, committed 2026-10-14), says of its `migrate` step: "The `migrate` step compares the files in `supabase/migrations` with the branch's migration history and applies every file without a history entry." Its list of cases says: "A migration file with a timestamp older than the latest applied migration still runs and the step finishes with a warning." So the integration does not refuse an older migration. It runs it after every migration already applied, out of the filename order that `supabase db reset` follows locally, and the check passes with only a warning.
- `supabase migration new` names a file from the current UTC time. Migrations on `main` already run ahead of the clock: #146 merged `20261018090000_study_days.sql` on 2026-10-17. A migration made the same day takes an earlier name. Locally it runs before `study_days`; in production it runs after it. A migration written against the schema it sorts after can then meet a different schema in production. Found in the PM's review of #146, recorded as issue #149.

## Decision

- **Naming.** A new migration's version, the 14 digits its name starts with, is later than every migration on `main`. A contributor names it from the current UTC time, as `supabase migration new` does, when that is later. Otherwise the contributor uses the latest version on `main` plus one second. On 2026-10-18, before 09:00:01 UTC, that is `20261018090001`.
- **Check.** `check-migration-order.sh`, run by `make lint`, fails when a migration file that `main` lacks has a version not later than the latest on `main`. It also fails when a migration's name does not start with 14 digits. In CI, `main` is the first parent of the merge commit that a pull request is checked out as: the ubuntu job's checkout fetches two commits deep for it. Locally, `main` is where `HEAD` left `origin/main`.
- **Test.** `check-migration-order.test.sh`, run by `make test`, builds repositories in a temporary directory and runs the check on a merge commit cloned two commits deep, as CI checks one out, and on a branch beside `origin/main`.

## Consequences

- A migration runs in production in the order it runs locally, unless two pull requests both pass against the same `main`. If one merges and then the other, which sorts before it, merges without a new CI run, the second still runs out of order. GitHub's "Require branches to be up to date before merging" setting would force that run. It is the owner's choice, and it is recorded under `server.md`'s open questions.
- A name may run further ahead of the clock with each migration made on the same day. The name orders migrations and records nothing else.

## Signs the decision was wrong

- A migration merged ahead of one that sorts after it, as the open question allows, and production and a local reset disagree on the schema.
- Migration names run so far ahead of the clock that contributors stop reading them as times.
