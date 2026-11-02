# ADR 0130: Retry a failed photo once within one usage, and record each extraction's outcome

> Status: accepted
> Date: 2026-11-01

Append-only: once merged, the body below is not rewritten. A fact later found wrong is corrected in an appended note, not edited out; a revised decision is a new ADR that supersedes this one.

## Context

- **Issue #508**, the owner's direction of 2026-11-01:
  - retry on failure, partial failure included, and automatically;
  - the server retries once on its own, and the photo counts once against the limit;
  - each extraction's result and failure is recorded and shown in the admin area, which #509 builds.
- **Before this change:**
  - The function made one model call per photo ([ADR 0071](0071-give-each-user-a-plan-whose-model-and-daily-limit-an-admin-sets-in-the-database-and-make-one-model-call-per-photo.md)). Invalid output, an HTTP or network failure and a call past the 60 s timeout ([ADR 0124](0124-send-a-fixed-output-contract-after-every-prompt-version-and-keep-a-reply-s-valid-cards.md)) were each `502 model_error` at once.
  - `private.extraction_calls` recorded each counted photo's plan, model and prompt version ([ADR 0073](0073-keep-the-extraction-prompt-as-append-only-versions-in-the-database-served-by-an-active-and-an-admin-only-test-label-and-record-what-served-each-call.md)), not how it ended. The failures of 2026-10-29 (#506) could not be traced to a cause: the log line was the only record, and Vercel's hobby plan keeps runtime logs for one hour (#508).
- **The Edge Function's limits** (`supabase.com/docs/guides/functions/limits`, read 2026-11-01): wall clock 150 s on the free plan and 400 s on paid plans; request idle timeout 150 s, after which the platform answers `504`; CPU time 2 s, which awaiting a model call does not use.
- **Alternatives considered:**
  - **The retry inside `extractCards`**, the call the eval shares. The eval would then measure two calls as one, its budget check would price one call for an image that may cost two, and its invalid-output count would stop measuring the prompt. The retry is the handler's, and the eval keeps measuring one call.
  - **A retry on another model.** ADR 0071 removed the Sonnet retry, and a plan's model is the admin's choice. The retry uses the plan's model.
  - **No time bound on the retry.** A first call timed out at 60 s, retried and timed out again, ends past 120 s; a later start would end past the 150 s limit, where the platform answers `504` and the outcome is never recorded.
  - **Recording the outcome in a table of its own.** Every counted photo already has one call record, deleted with its usage row and its user. The outcome is more columns of that row.
  - **Finding the call to finish by the user's latest record.** The app reads three photos at a time ([ADR 0094](0094-read-a-photo-import-of-up-to-fifty-photos-three-at-a-time-as-an-app-level-job-kept-on-the-device-and-offered-again-after-a-restart.md)), so a user's requests overlap. `begin_extraction` names the usage row it recorded instead.

## Decision

- **One retry.** When the first model call ends as `model_error`, a timeout included, or as `invalid_output`, the function makes one more call for the same photo, with the same model, prompt and image, in the same request. A valid empty list and a reply with kept cards are not retried.
  - The retry starts only while fewer than 75 s of the request have passed (`RETRY_START_LIMIT_MS`), so a retry that times out at 60 s ends by about 135 s, under the 150 s limits.
  - The photo counts once: `begin_extraction` runs once per request, before the first call.
  - The answer is the last call's: its cards, `no_cards`, or `502 model_error`. The log line's tokens are both calls' sum.
- **This supersedes ADR 0071's "one model call per photo" in part**: a photo still makes one call when it answers, and at most two.
- **The outcome.** `private.extraction_calls` gains, for each counted photo, `outcome` (`ok`, `no_cards`, `invalid_output` or `model_error`), `attempts` (1 or 2), `latency_ms`, `cards_returned` and `cards_dropped` of the last reply, and `failures`, the failure of each call that failed in order (`invalid_output`, `model_error` or `timeout`). No image, card or prompt text is recorded.
  - A check keeps the parts in agreement: all null, or all set with one failure per call, one fewer when the last call answered, and cards only on `ok`.
  - `begin_extraction` returns the usage row it recorded as `usage_id`. `public.finish_extraction`, executable only by `service_role`, records the outcome on that row's call once, before the function answers. The record is telemetry: when it fails, the photo is answered as it would have been, and the log line's `outcome_recorded` is false. A row whose outcome stays null was counted before this change, or its request ended unexpectedly.
- **The admin reads**, each checking the role as [ADR 0070](0070-run-the-service-from-a-web-admin-area-whose-role-and-audit-log-live-in-the-database-and-whose-every-read-and-write-is-checked-there.md) decides: `admin_extraction_calls(before, page_size)`, the recorded calls newest first, and `admin_extraction_failures(days)`, each UTC day's calls by prompt version with each outcome's count, the retried and recovered calls, the share failed and the unrecorded calls. #509 shows them.
- **The migration** `20261031181717_extraction_outcomes.sql` adds six nullable columns and the check, replaces `begin_extraction` with its body unchanged and one returned column more, and adds the three functions. It changes no row.

## Consequences

- A transient failure no longer fails the photo, and the user pays one photo for it. A failure that recurs costs two calls; a photo that answers costs one, as before.
- A failed photo's answer now takes up to about 135 s. The web's photo read aborts its request at 90 s (`web/src/features/decks/read-photo.ts`), so a retry after a first call timed out ends after the web has shown a failure, the photo counted and its cards lost.
- Each failure is readable afterwards by its kind, day and prompt version, without the logs.
- Merging deploys the migration and the function in no stated order. Should the function arrive first, `begin_extraction` names no usage row yet and each allowed photo answers `500` after it is counted, until the migration applies, as ADR 0073 accepted for its own deploy.
- A failed record leaves the call without an outcome, under `unrecorded`, and only the log line, kept briefly, says why.

## Signs the decision was wrong

- Retried photos mostly fail again: the failures are not transient, and the second call only doubles their cost.
- Recovered calls are frequent on one prompt version: the retry hides a prompt that breaks the contract, which the eval's single call should have caught.
- Retried requests often end past the web's 90 s, so the web shows failures the server recovered from.
- The outcome record and the log line disagree, so one of them is not where an operator should look.
