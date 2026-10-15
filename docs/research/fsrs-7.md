# FSRS-7 assessment

Whether to move the engine from FSRS-6 (py-fsrs 6.3.2, [ADR 0003](../architecture/adr/0003-fsrs-engine.md)) to FSRS-7, answered for issue #54 from the sources listed under §Sources, read on 2026-10-15; every external claim names the source and revision it holds for.

## 1. Reference implementation

- **py-fsrs has none.** The latest release is still v6.3.2 (PyPI `fsrs` 6.3.2; [py-fsrs] `main` is that tag's commit). Its `fsrs/scheduler.py` has the 21 FSRS-6 parameters and no FSRS-7 code. `engine/tests/fixtures/generate.py` cannot be pointed at a newer py-fsrs.
- **fsrs-rs has it on `main`, unreleased.** FSRS-7 merged on 2026-09-08 (fsrs-rs PRs #395, #412, #426), after the last release, v6.6.2 (2026-08-28; crates.io `fsrs` 6.6.2 is the latest version). At [fsrs-rs] `main`, `src/model_v7.rs` and `src/inference_v7.rs` hold it, and `FSRS::new` picks FSRS-7 from 34 parameters and FSRS-6 from 17, 19 or 21. It computes in `f32`.
- **ts-fsrs has it in a beta.** The `preview` branch ([ts-fsrs]) carries FSRS-7 (PR #520, merged 2026-09-18; corrected by #540 on 2026-09-24). It ships on npm as `ts-fsrs@6.0.0-beta.14` (2026-10-09, dist-tag `beta`). The stable `ts-fsrs@5.4.2` (dist-tag `latest`) is FSRS-6. Its FSRS-7 guide says the implementation rounds each new state value to eight decimals, and it computes in `f64`.
- **The definition is still moving.**
  - [srs-benchmark] `models/fsrs_v7.py` has had 22 commits since the one that added FSRS-7 on 2026-03-11. The last of them, PR #348 (2026-08-29), changed the parameter count to 34.
  - The same revision's README still lists 35 default parameters under §Default Parameters. Those values differ from the 34 in `init_w`.
  - fsrs-rs issue #445 (open) reports that `clip_fsrs7_parameters` drops a lower bound that srs-benchmark enforces.
  - fsrs-rs issue #446 (open) asks to align crate major versions with FSRS versions, because 6.x crates now hold FSRS-7.
  - fsrs-rs's own `docs/COMPATIBILITY.MD` at [fsrs-rs] says `FSRS::new(&[])` gives FSRS-6 defaults, while `src/model.rs` at the same commit maps an empty parameter list to FSRS-7 (PR #455).
- **Anki has not shipped it.** Anki's latest release, 26.09.3, and its `main` at [anki] both lock `fsrs` 6.6.2.
- **Usable for reference values:** only from an unreleased commit (fsrs-rs) or a beta (ts-fsrs), and the two differ in float width. A generator would pin one of them by commit or exact beta version. A later change to the definition would change the expected values.

## 2. What changes

Read from [fsrs-rs] `src/model_v7.rs` and the ts-fsrs FSRS-7 guide (`docs/src/en-US/guide/model/fsrs-7.mdx` at [ts-fsrs]), which agree on the formulas.

| Aspect | FSRS-6 (engine today) | FSRS-7 |
|---|---|---|
| Parameters | 21 | 34, defaults in [fsrs-rs] `src/inference_v7.rs` |
| State | stability, difficulty, last review | slow stability, fast stability (`stability_fast`), difficulty, last review |
| Forgetting curve | one power curve, decay `w[20]` | a weighted mixture of a fast and a slow power curve; the weights depend on both stabilities and difficulty |
| Elapsed time | whole days; under one day takes a separate same-day stability formula | fractional days, one update for every elapsed time, zero included; no separate same-day formula |
| Stability after review | one long-term update, one same-day update | the same update shape run twice, once per trace with its own 8 parameters, on the mixed recall for the slow trace and the fast trace's own recall for the fast one; on Again the fast stability is capped at 0.8 × the slow one |
| Difficulty | linear damping, mean reversion by `w[7]` | linear damping, a lapse's change scaled by recall + 0.1, mean reversion fixed at 1% |
| Interval | closed form, rounded to whole days, at least 1 | solved numerically (up to seven Newton steps, then bisection), fractional days, as short as one second |
| Minimum stability | 0.001 (py-fsrs 6.3.2) | 0.0001 (fsrs-rs, ts-fsrs) |

- **Stored state.** `stability`, `difficulty` and `last_review` do not suffice: the interval and recall depend on `stability_fast` too, so `card_states` needs that value. FSRS-7 still needs no more history: a state of three numbers plus the last review time folds forward review by review, as now.
- **The reviews table suffices for a recompute.** FSRS-7 reads the elapsed time between reviews in fractional days. `reviews.reviewed_at` holds the time to the second ([`study.md`](../architecture/study.md) §Storage), so a fold over stored reviews can feed it exactly.
- **New-card values at default parameters** ([fsrs-rs] `src/inference.rs`, `next_states` doc example): Again gives stability 0.1104 and an interval of 3.8e-5 days (about 3 seconds), Hard 0.597 days, Good 4.78 days, Easy 53.9 days. FSRS-6 gives 1, 1, 2 and 8 days for the same new card with the engine's settings.

## 3. Evidence

All figures are from [srs-benchmark], dataset `open-spaced-repetition/anki-revlogs-10k` (about 727 million reviews from 10,000 Anki users). Each metric is the mean over users, weighted equally, with a 99% bootstrap interval (`evaluate.py`). Lower log loss is better.

- **README rows, per-user optimized parameters:**

  | Table | FSRS-7 | FSRS-7 recency | FSRS-6 |
  |---|---|---|---|
  | With same-day reviews (10,000 users) | 0.3206±0.0040 | 0.3178±0.0040 | 0.3842±0.0051 |
  | Without same-day reviews (9,999 users) | 0.3401±0.0043 | 0.3370±0.0042 | 0.3460±0.0042 |

  - With same-day reviews the intervals are far apart. Without them, the FSRS-7 and FSRS-6 intervals overlap, so the README's own figures do not separate them there.
  - "Recency" weights newer reviews more in training, which needs per-user optimization.
- **This app runs default parameters** ([`engine.md`](../architecture/engine.md)), so the relevant pair is FSRS-7 against FSRS-6 with default parameters. The README shows only FSRS-7's default row. `evaluate.py` leaves FSRS-6's out, but its result files are committed.
  - I computed the paired per-user difference from those files, `result/<name>.jsonl`, with a throwaway script (2,000 bootstrap resamples, seed 42).
  - The same script reproduces the README's 0.3842, 0.3206, 0.3178 and 0.3399 from their files, which checks the method.

  | Pair (log loss) | Users | FSRS-7 | FSRS-6 | Difference, 99% interval | Users FSRS-7 wins |
  |---|---|---|---|---|---|
  | Default parameters, with same-day (`FSRS-7-default-short-secs`, `FSRS-6-default-short-secs`) | 10,000 | 0.3399 | 0.4886 | −0.149 (−0.154, −0.144) | 91.7% |
  | Default parameters, without same-day (`FSRS-7-default-short-secs-equalize_test_with_non_secs`, `FSRS-6-default-short`) | 9,999 | 0.3620 | 0.3664 | −0.0043 (−0.0050, −0.0037) | 61.1% |
  | Optimized, with same-day (`FSRS-7-short-secs`, `FSRS-6-short-secs`) | 10,000 | 0.3206 | 0.3842 | −0.064 (−0.065, −0.062) | 96.1% |
  | Optimized, without same-day (`FSRS-7-short-secs-equalize_test_with_non_secs`, `FSRS-6-short`) | 9,999 | 0.3401 | 0.3460 | −0.0059 (−0.0064, −0.0055) | 79.4% |

  - On reviews a day or more apart, FSRS-7 at default parameters is better than FSRS-6 by a small margin. The paired interval excludes zero, but FSRS-7 is better for only 61% of users.
  - The large gain is in predicting same-day reviews, where FSRS-6 at default parameters does worse than the constant baseline AVG (0.3816 in the README).
- **What the benchmark measures.** It measures how well a model predicts recall. It does not measure how much users remember under the model's schedule, or how many reviews they spend. The README's "FSRS-7 sched. penalties" rows exist because FSRS-7's best-predicting parameters gave schedules the authors judged unreasonable: very short same-day intervals at high desired retention, and large jumps at low retention.
- **Data from another app.** The data are Anki review logs, with four buttons, learning steps and Anki's timing. This app's two buttons and 3–5-card re-shows are not in them.
- **Nothing peer-reviewed.** The papers the FSRS wiki lists for the lineage ([wiki] `Research-resources.md`: Ye, Su & Cao, KDD 2022; Su et al., IEEE TKDE 2023) cover the MaiMemo DHP model FSRS started from, not FSRS-6 or FSRS-7. A web search on 2026-10-15 found no FSRS-7 paper. The evidence is the benchmark repository, maintained by FSRS's authors.

## 4. Fit with this app

### Same-day re-shows

Today each "Don't know" re-show is a review passed to the engine ([`study.md`](../architecture/study.md) §Session).

- **FSRS-6 on a re-show.** A review under one day after the last uses the same-day formula, which ignores how much time passed. Recall is computed from whole days, so it reads 1 for a re-show minutes later.
- **FSRS-7 on a re-show.** It computes recall at the actual minutes elapsed. A success when recall was near 1 raises stability little, and a failure lowers it in proportion to how surprising it was. The order and spacing of re-shows within a session then change the state, where FSRS-6 sees only their count and ratings.
- **The intervals change in kind.** I transcribed fsrs-rs's FSRS-7 into a throwaway Python script (f64) and checked it against the new-card values above, which it matches to the fifth significant figure. Against py-fsrs 6.3.2 with the engine's settings, run with `uv`, it gave these due times at default parameters and retention 0.9:

  | History | FSRS-7 next interval | FSRS-6 next interval |
  |---|---|---|
  | Don't know, Don't know 5 min later, Know 5 min later | 0.0037 days (5 minutes) | 1 day |
  | then Know the next day | 0.097 days (2.3 hours) | 1 day |
  | Know, Know on due, Don't know on due (a lapse) | 0.051 days (73 minutes) | 2 days |
  | Know, Know the next day | 18.0 days | 7 days |

- **The whole-day rule cannot hold unchanged.** FSRS-7 schedules new and lapsed cards minutes or hours out. The app's due time is whole days ([ADR 0003](../architecture/adr/0003-fsrs-engine.md), "No learning steps" in `engine.md`). Two answers exist; choosing between them is a product decision for the owner.
  - Keep sub-day due times. A card would come due again later the same day, so the queue built at session open picks it up in the next session. That is closer to what FSRS-7 was designed and benchmarked for.
  - Round each interval up to at least one day. This keeps today's behaviour, but every early due time is then later than FSRS-7 intends, and the benchmark does not measure FSRS-7 used that way.
- **Re-shows come later than FSRS-7's own interval.** After a "Don't know" on a new card, FSRS-7's interval at retention 0.9 is seconds. The 3–5-card gap ([ADR 0009](../architecture/adr/0009-multi-deck-session-and-random-queue-order.md)) is longer, so a re-show becomes an overdue same-day review, which FSRS-7 models, rather than one it never sees.

### Fuzz

- **The formula is independent of the model.** Fuzz moves only the due time ([ADR 0012](../architecture/adr/0012-fuzz-review-intervals.md)), and py-fsrs 6.3.2's formula takes an interval and a factor. It can be applied to an FSRS-7 interval unchanged, and the stored `fuzz_factor` per review keeps its meaning.
- **No upstream FSRS-7 fuzz to follow.** py-fsrs has no FSRS-7, and fsrs-rs does not fuzz.
- **ts-fsrs v6 differs from py-fsrs.** At [ts-fsrs] `packages/fsrs/src/middlewares/fuzzing/core.ts`, it keeps py-fsrs's ranges and 2.5-day threshold, but:
  - it floors the pick where py-fsrs rounds;
  - it raises the lower end to elapsed days + 1;
  - it keeps intervals under 2.5 days fractional.
- **Two decisions needed.** One: how a fractional interval enters the whole-day fuzz formula (rounded first, or fuzzed as a fraction). Two: whether the engine's fuzz keeps following py-fsrs 6.3.2 or moves to ts-fsrs's. Either way, ADR 0012's "follows py-fsrs" stops being a reference anyone maintains for FSRS-7.

## 5. Migration

### Recompute from history

- **Mechanically, yes.** FSRS-7 states come only from replaying reviews: the ts-fsrs FSRS-7 guide states that FSRS-6 weights and states cannot be converted. `Scheduler.fold` already recomputes a card from its non-deleted reviews in `reviewed_at` order ([`study.md`](../architecture/study.md) §Surface and location, [ADR 0015](../architecture/adr/0015-sync-protocol-and-conflict-policy.md)).
- **Pending due dates.** The ts-fsrs migration guide (`docs/src/en-US/guide/migration.mdx` at [ts-fsrs]) advises rebuilding the memory state but keeping each card's existing due date until its next review. Recomputing due dates too would move many cards at once, with the intervals in §4 longer than FSRS-6's for known cards and shorter for failed ones. The owner decides which.
- **Rows without full history.** Every reviewed card has its reviews locally, and sync unions them ([ADR 0015](../architecture/adr/0015-sync-protocol-and-conflict-policy.md)), so missing history is not expected here. A review whose card was deleted stays on the server and needs no state.
- **Schema change.** `card_states` gains `stability_fast`: a local schema migration and a server migration of `public.card_states` ([`server.md`](../architecture/server.md)), applied by the owner.

### A mixed fleet

The same reviews would be synced by FSRS-6 and FSRS-7 devices at once.

- **Reviews stay compatible.** Their columns (rating, time, fuzz factor) do not change.
- **Card states conflict.** A pulled state replaces a synced local one, and a device that pulled a review refolds the card and pushes the result ([`sync.md`](../architecture/sync.md)). Mixed devices would therefore overwrite each other's states:
  - an FSRS-6 device would push an FSRS-6 state with no `stability_fast`;
  - an FSRS-6 device would take an FSRS-7 state, and its sub-day due time, as its own.
  - ADR 0015 names "a recomputed card state on one device differs from another's for the same reviews" as a sign that decision was wrong.
- **What a rollout needs, before the first FSRS-7 build ships:**
  - each state marked with the model that computed it;
  - each device ignoring and refolding a state of a model it does not run;
  - and either a minimum app version enforced at sign-in or sync, or FSRS-7 states kept in a column or table FSRS-6 builds do not read.
  - Builds already installed cannot be changed, so whichever is chosen has to work against them as they are.

### The web build (#43)

- Issue #43 builds `engine-wasm/` from `engine/` by path, and runs the reference values under WebAssembly (PR #49, open).
- An FSRS-7 engine reaches the web by regenerating `engine-wasm/pkg/`. The WASM surface gains `stability_fast` in the state parts it passes.
- The web app shares the server's `card_states`, so it is one more member of the mixed fleet above.
- If the move happens after #43 merges, the engine, the bridge and the WASM crate change in one PR, so no build ships a different model from another.

## 6. Cost

A size estimate against the code as it stands (`engine/src/fsrs.rs` 204 lines, `engine/src/lib.rs` 305).

| Work | Size |
|---|---|
| FSRS-7 formulas and the numeric interval solver in `engine/` | medium: about the size of `fsrs.rs` again |
| `MemoryState` and its parts gain `stability_fast`; typed errors for it | small |
| Reference generator on a new source (ts-fsrs beta via Node, or fsrs-rs at a commit via Rust), pinned, with a lock file and new fixtures | medium |
| Bridge surface, regenerated bindings, `Scheduler`, `Scheduler.fold` | small to medium |
| Local schema migration and fold of every card on upgrade; server migration; sync of the new column | medium |
| Model marker and mixed-fleet handling (§5) | medium |
| WASM crate surface and regenerated package (#43) | small |
| Sub-day due times, if chosen: the queue and today's counts read due times within a day | medium |
| ADR, `engine.md`, `study.md`, `sync.md`, `server.md` | small |

Risks:

- **The definition changes again.** It changed on 2026-08-29 (§1), after it was called finished in fsrs-rs issue #428. Each change regenerates the reference values and changes users' schedules.
- **Reference values are not exact.** fsrs-rs computes in `f32`, and ts-fsrs rounds states to eight decimals. Matching either needs a tolerance, or copying its float behaviour, which ADR 0003 avoided by matching py-fsrs exactly.
- **The interval is iterative.** It is a Newton solve with a bisection fallback. Due times match a reference only if the solver, its start and its iteration count match too.
- **The benchmark result does not cover this app's use.** Default parameters with a whole-day floor are not measured anywhere (§3, §4).
- **No upstream fuzz.** No upstream FSRS-7 fuzz exists to follow (§4).
- **Mixed-fleet sync can mix states** if the rollout guard is missing (§5).

## 7. Recommendation

**Wait.** Do not move now. Reopen when all of these hold:

1. **A release exists.** FSRS-7 is in a tagged release usable for reference values, and its definition has not changed for a period the owner sets. The release could be a crates.io `fsrs` version or a stable ts-fsrs 6.0.0 that contains it.
2. **The owner has chosen the due-time policy:** sub-day due times, or a one-day floor (§4).
3. **A rollout path is decided** for card states across app versions (§5), and is in place before an FSRS-7 build ships.

Why wait rather than no-go: the gain is real where this app differs most from FSRS-6's design. At default parameters, with same-day reviews, log loss falls from 0.489 to 0.340, better for 92% of users (§3). The cost is mostly one-time, and it is lower against a stable definition.

Why not go: reference values can only come from unreleased code today, and the definition changed six weeks ago. The decision also changes the product's whole-day scheduling rule, which this report cannot make.

## Sources

- [srs-benchmark] — `open-spaced-repetition/srs-benchmark` at commit `bd9110f791e5b37282c55a9aa8db35f68f0c4aa2` (2026-09-18): `README.md`, `evaluate.py`, `models/fsrs_v7.py`, and the result files named in §3; history of `models/fsrs_v7.py`; PR #348.
- [fsrs-rs] — `open-spaced-repetition/fsrs-rs` `main` at commit `0a5737406a0c5c7a5259b144738cbe4a0b649d76` (2026-10-09): `src/model.rs`, `src/model_v7.rs`, `src/inference.rs`, `src/inference_v7.rs`, `docs/COMPATIBILITY.MD`; release v6.6.2 (commit `6088949b99d44f46f5328fd7289d209b9a842b68`); crates.io `fsrs` versions; issues #428, #445, #446; PRs #395, #412, #426, #455.
- [ts-fsrs] — `open-spaced-repetition/ts-fsrs` branch `preview` at commit `73fbe1783afb9393235f64326cfcbea2a635d9a8` (2026-10-11): `docs/src/en-US/guide/model/fsrs-7.mdx`, `docs/src/en-US/guide/migration.mdx`, `packages/fsrs/src/middlewares/fuzzing/core.ts`, `packages/fsrs/package.json` (6.0.0-beta.14); npm dist-tags of `ts-fsrs`; PRs #520, #540.
- [py-fsrs] — `open-spaced-repetition/py-fsrs` `main` at commit `9446cb06605c597a063aeee49f7d188d42e34dc2` (tag `v6.3.2`): `fsrs/scheduler.py`; PyPI `fsrs` release list.
- [wiki] — `open-spaced-repetition/awesome-fsrs` wiki at commit `7bcf7dc343fc81d0fc55db2705c8b8fe85c2daa5`: `The-Algorithm.md`, which has no FSRS-7 section, and `Research-resources.md`.
- [anki] — `ankitects/anki` tag `26.09.3` and `main` at commit `c4852282f3fa43e5eddb5da740b7956602368ba9`: `Cargo.lock`.
