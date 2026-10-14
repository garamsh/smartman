# ADR 0014: Run the database tests on a throwaway local stack of their own, never on the shared one

> Status: accepted
> Date: 2026-10-15

Append-only: once merged, the body below is not rewritten. A fact later found wrong is corrected in an appended note, not edited out; a revised decision is a new ADR that supersedes this one.

## Context

- [ADR 0010](0010-server-schema-and-row-level-security.md) decided that `supabase/test-db.sh` starts the local stack if none is running, resets it, runs the tests, and stops the stack it started. The stack is named from `project_id` in `supabase/config.toml`, so every checkout of this repository on one host shares it.
- Issue #37: on 2026-10-15, `make ci` failed twice in `test-db.sh` with `DbSetupError` while another worktree was using the same stack. A run can also reset the database under another run's tests, or stop a stack another run started. Workers run in parallel worktrees by design, so this recurs.
- Two copies of that script, run at once against one stack, both exited 1 in each of three rounds, in the reproduction the pull request closing #37 records.
- Supabase CLI 2.120.0 takes the local project id from `SUPABASE_PROJECT_ID` before `config.toml` (`apps/cli/src/commands/stop/SIDE_EFFECTS.md` at tag `v2.120.0`), and with `SUPABASE_DB_PORT` set, `supabase start` and `supabase test db --local` used that port instead of `[db] port` (observed on this CLI release).
- `supabase stop` prunes containers, volumes and networks. With two projects stopping at once, one stop failed with `StopNetworkPruneError` (observed with CLI 2.120.0 on Docker 29.5.2), and the failed stop can be run again.
- Rejected: a host-wide lock that serializes runs on the shared stack. Runs would wait for each other, and a run would still reset a stack that a developer started for the app.

## Decision

- **Own stack.** Each run of `test-db.sh` starts a stack with only Postgres, under the project id `smartman_test_<port>`, publishing its database on `<port>`. Starting it applies the migrations, so the script runs no reset. It never starts, resets or stops the `smartman` stack.
- **Port.** The port is the first one in 54400–54499 that the run reserves by creating its directory under `${TMPDIR:-/tmp}/smartman-test-db/` and on which nothing on the host is listening. Creating a directory is atomic, so two concurrent runs never take the same port.
- **Stop.** The script stops the stack, deleting its data, and releases the port on every exit, interrupts included. It retries a failed stop up to ten times, two seconds apart. If the stack is still running after that, the run fails and prints the command that removes it.
- **Unchanged.** The skip where Docker does not answer, the printed count, and CI's ubuntu job stay as ADR 0010 set them.

## Consequences

- Checkouts run `make test` at the same time without waiting for or failing each other, up to 100 runs at once on one host.
- `make test` no longer touches a running `smartman` stack, so the rows in it survive the tests.
- Every run pays for starting a stack, about one minute on a developer's Mac, even when a stack is already running.
- A run killed with `SIGKILL` leaves its stack running, and its reservation directory makes later runs skip that port. Removing the stack and the directory frees the port again.

## Signs the decision was wrong

- Starting a stack per run makes `make test` too slow to run before each push.
- Runs fail because something other than these runs holds ports in 54400–54499.
- Test stacks remain after runs that were not killed, which would mean a stop that fails more often than the retry covers.
