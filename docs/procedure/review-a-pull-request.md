# Review a pull request

The order of the acts in a review of a pull request in this repository, the commands for each, and what the host does. What a review must carry is `docs/convention/review.md`; this file cites it and states none of it.

## Before the diff

1. List the changed paths without reading the diff: `gh pr diff <n> --name-only`.
2. Open `docs/convention/README.md` and, from its §Stack-neutral and §Stack-specific tables, pick every file whose Governs column covers a changed path. §Precedence there orders them where two apply.
3. Read those files, and `docs/convention/review.md` in full, from the files at the current `main` — `AGENTS.md` §Start here, every time gives the reason a remembered version is not read instead.
4. Where a changed path touches code or a decision, open `docs/architecture/README.md` too; its §Rules feed the Architecture row.
5. Read the task the pull request states — its issue and that issue's comments, or its Summary where it names no issue. `review.md` §What each check verifies, "Scope is measured against the task", names it as the measure.

## Reading the diff

1. Fetch first, so `main` is the one GitHub holds: `git fetch origin`.
2. Measure scope from the merge base: `git diff --stat origin/main...origin/<branch>`, three dots. In git 2.50.1, `git diff A...B` compares B against the merge base of A and B, while the two-dot `git diff A..B` compares the two tips, so every change merged to `main` after the branch was cut shows up as if the branch reverted it. `gh pr diff <n>` shows the same set the three-dot form does.
3. Check each changed line against the conventions read above. Each violation is cited as `review.md` §Citing violations states, and tagged as §Blockers and nits states.

## Confirming the run

The two checks this section serves are `review.md` §Submitting a review, "Confirm the checks belong to the head commit" and "A conclusion is not a verdict unless the run did the work".

1. Read the head: `gh pr view <n> --json headRefOid,headRefName`.
2. List the runs on the branch with the commit each ran on: `gh run list --branch <headRefName> --json databaseId,headSha,conclusion,event`. Take the run whose `headSha` equals `headRefOid`; a run on any other commit is not a run on the head.
3. Count the steps that ran: `gh run view <databaseId> --json jobs --jq '.jobs[] | {name, conclusion, steps: [.steps[] | {name, conclusion}]}'`.
4. Read what the steps selected: `gh run view <databaseId> --log`. In this repository each job runs `make` targets, and the lines in which a check names what it was `selected by` give the count it selected; the counts are the work selected.

## Posting the verdict

1. Write the body in a file, holding what `review.md` §Submitting a review names.
2. Where the reviewer opened the pull request from the same account, the state to submit is the one `review.md` §Single-account setups names. Where the reviewer also wrote the change, `review.md` §Reviewing your own change applies.
3. Submit it: `gh pr review <n> --comment --body-file <file>`, or `--approve` / `--request-changes` where the state allows it, per `gh pr review --help` in gh 2.102.0.
4. To merge, the method and the commit it leaves are `docs/convention/git.md` §PRs and §Commits, the second paragraph of §Commits, beginning "An author is a person", naming what the subject must carry: `gh pr merge <n> --squash --body-file <file>`, then read the commit on `main` against the squashed commits. `gh api repos/garamsh/smartman --jq .squash_merge_commit_title` reads `COMMIT_OR_PR_TITLE`, and the subject lands as the title with the number: `git show -s --format=%s cf494ca6fcc4fbd2e934f3ad5acdcfd191d141f4` reads #95's title followed by `(#95)`.

## Host facts

Observed on this host on 2026-10-16, with gh 2.102.0 on macOS 26.5.2.

- `gh pr view <n>` and `gh issue view <n>` work with and without `--json`.
- `gh run list --commit <sha>` given an abbreviated SHA prints nothing and exits 0, which reads the same as a head with no run — the case `review.md` §Submitting a review, "Confirm the checks belong to the head commit", treats as an unverified change. On `cf494ca6fcc4fbd2e934f3ad5acdcfd191d141f4`, `gh run list --commit` listed one run for the full name and none for its first 8 characters. Passing the full 40-character `headRefOid` works.
