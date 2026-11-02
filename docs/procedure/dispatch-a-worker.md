# Dispatch a worker

The acts that start a worker through Orca on this host, bind it to its role, wait on it, and release it once it settles. No convention in `docs/convention/` governs dispatch; the role a worker holds is `AGENTS.md` §Roles, and the branch it works on is `docs/convention/git.md` §Branches.

## Host facts

Read from `orca` 1.4.220 on this host, macOS 26.5.2, on 2026-10-16: the `--help` output of each command named, and the process list. A fact that rests on what was observed in a dispatch names that dispatch's date and evidence itself.

- A worker launched by typing `claude --agent worker --permission-mode bypassPermissions` into its worktree's terminal runs with that command line (`ps -axo command`), so the Worker role reaches it through its role document and not through the dispatch's text alone. The PM runs as `claude --teammate-mode auto --dangerously-skip-permissions --agent pm`.
- `orchestration worker-start` takes `--task <task_id>` or `--spec <text>`. `worker-start --help` states "When reusing --terminal, pass --worktree for that terminal; current means the coordinator worktree."
- `worker-release` "closes only the exact coordinator-owned agent terminal of that worker" and "Never closes setup terminals, configured tabs, reused or pre-existing terminals". A worker started on a terminal its worktree already had is a reused terminal, so `terminal close --worktree <selector> --all` closes it.
- `worktree rm` "attempts to delete the checked-out local branch" and "Orca retains branches it knows predated the worktree and any branch whose changes it cannot prove are already merged". This repository squash-merges (`git.md` §PRs), so a merged branch's tip is not an ancestor of `main` and a retained branch is the expected result. The worktree's directory was still present for several seconds after `worktree rm --force` returned, on each release on 2026-10-16, so its removal is confirmed by the directory's absence and not by the command's exit.
- `orchestration check --help` states that `--types` "is the wake condition for --wait; a returned Delivery is always the whole FIFO batch, so it is never filtered by type", that "A bound Run replays the same Delivery until --ack or all its messages are marked read, even with --types", and that `--wait` "Emits JSON keepalive lines to stderr every 15s", filtered with `jq "select(._keepalive|not)"` when the streams are merged.
- `orchestration task-create` needs a Run bound to the coordinator's terminal. `run-use --help` reads `--id <run_id>`; after the PM's process was replaced on 2026-10-16, `orca orchestration run-use --id <run_id> --json` rebound the existing Run.
- A worker that asks through `orchestration ask` blocks until the question is answered with `orchestration reply`, whose `--help` reads `Usage: orca orchestration reply --id <msg_id> --body <text> [--run <run_id>] ...`. A `send` to the dispatch does not wake it. On 2026-10-16 the issue #88 worker asked through `ask` (message `msg_348a26cf9c55`); answered with `orca orchestration send --to dispatch:<ctx>`, it stayed idle for about 50 minutes, and answered with `orca orchestration reply --run <run> --id msg_348a26cf9c55 --body <text>`, it resumed within seconds, its terminal showing the background `ask ... --resume msg_348a26cf9c55` completing (issue #114).
- On 2026-10-17, `worker-start --task <task_id>` on the terminal of a worker whose dispatch had completed was refused with `agent_unconfigured`, "is not running a recognized agent", twice, while the worker's agent sat at its prompt, on the terminals `term_c0754e34-f215-4b84-a24b-900ddaaa9467` and `term_d726c963-8cfd-4edd-865f-417bb3ad5ebb`. The same reuse succeeded on other workers' terminals that day. The PM released each refused worker and dispatched a fresh one.
- Building the app in a worktree leaves an Xcode derived-data folder `~/Library/Developer/Xcode/DerivedData/Runner-*` whose `info.plist` key `WorkspacePath` names that worktree. Nothing in Orca removes it.

## Start

1. Create the worktree: `orca worktree create --repo id:<repo_id> --name <name> --no-parent --setup skip --issue <n> --json`, and rename its branch per `git.md` §Branches with `git -C <path> branch -m <branch>`.
2. Bind the role: send `claude --agent worker --permission-mode bypassPermissions` with Enter to the worktree's one terminal (`orca terminal list --worktree id:<repo_id>::<path> --json`), and wait for it with `orca terminal wait --for tui-idle`.
3. Write the Task's text with `orca orchestration task-create`, naming the issue it implements, the branch, the paths it may change, and any number or name another in-flight task could also claim. Where the change edits a convention file to meet an obligation another convention file states, the Task asks for the citation of that obligation in the pull request body and not in the convention file: `docs/convention/README.md` §Independence, "A convention file does not send the reader to another convention file", and `docs/convention/README.md` §Stack-specific, "the files do not point at each other".
4. Start it on that terminal: `orca orchestration worker-start --task <task_id> --terminal <handle> --worktree "id:<repo_id>::<path>" --json`. For a second round on the same worker, create a new Task and start it the same way; where that start is refused with `agent_unconfigured`, release the worker and dispatch a fresh one (§Host facts).

## Confirm the three bindings

A start that exits 0 is the launcher's report, not an observation. Confirm each binding by asking the host:

1. **The worktree exists:** `git worktree list` shows it on the branch named.
2. **The role took:** `orca terminal read --terminal <handle> --json` shows the `worker` agent label and the worker reading the issue and the files its role names.
3. **It runs on its own:** `orca terminal wait --for tui-busy` returns, a later read shows new output, and none of it is a permission prompt waiting on input.

## Wait

1. Wait on completion and its neighbours: `orca orchestration check --wait --types "worker_done,escalation,question" --timeout-ms <n> --json`. Leaving `heartbeat` out of `--types` keeps the wait blocked across beats.
2. On a wait that returns, read the batch from `.result.messages[]` and acknowledge it with `--ack <deliveryId>` taken from `.result.deliveryId`. A heartbeat shows the worker is alive, not that it is done.
3. Answer a `question` with `orca orchestration reply --run <run_id> --id <msg_id> --body <text>`, the id taken from the message in `.result.messages[]`. A `send` to the dispatch does not wake the waiting `ask` (§Host facts).
4. Judge whether a worker has settled by what it produced — commits on its branch (`git log origin/main..origin/<branch>`), a pull request (`gh pr list --head <branch> --json number,state`), a comment on its issue — rather than by its beats or its silence.

## Release

Releasing is three acts, each confirmed by asking the host afterwards rather than by the command's exit status.

1. **The terminal.** First confirm nothing the worker started still runs: `orca terminal list --worktree <selector> --json`, and the processes with a file open in that worktree: `lsof +D <worktree path>`. Then `orca orchestration worker-release --dispatch <dispatch_id>`, and `orca terminal close --worktree <selector> --all` for a terminal `worker-release` does not own. Confirm with `terminal list` again.
2. **The worktree.** `orca worktree rm --worktree <selector> --force`; confirm by the directory's absence and `git worktree list`, then `git worktree prune`. Remove the derived-data folder whose `WorkspacePath` names the worktree: `/usr/libexec/PlistBuddy -c "Print :WorkspacePath" <folder>/info.plist`.
3. **The branches.** Ask the host whether the work landed: `gh pr view <n> --json state,mergeCommit`. On `MERGED`, delete the local branch where `worktree rm` retained it, with `git branch -D <branch>`. The repository's `delete_branch_on_merge` reads `true` (`gh api repos/garamsh/knowno --jq .delete_branch_on_merge`), so GitHub deletes the remote branch on merge. Confirm with `git branch --list <branch>` and `git ls-remote --heads origin <branch>`, both empty.
