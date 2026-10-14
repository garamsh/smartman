# AI extraction

The `extract-cards` Edge Function that turns a photo of a vocabulary page into candidate cards, its limits and privacy, how its model is switched, and the eval that chooses the model.

## Current decisions

### Location

- The function is `supabase/functions/extract-cards/`, a Deno module with no third-party dependency: it calls Supabase Auth, PostgREST and OpenRouter with `fetch` ([ADR 0013](adr/0013-extract-cards-function-and-eval.md)).
- `index.ts` is its composition site: it reads the configuration once and passes `fetch`, the logger and the clock to the handler, which constructs none of them.
- The eval is `tools/eval/`, outside the function, so the deployed folder holds only the function. It imports the function's extraction module, so it measures the same prompt, schema and retry.
- Only the PM deploys the function and sets its secrets, after the pull request that changes it merges.

### Contract

- `POST` with the user's access token as `Authorization: Bearer`, and a JSON body:
  - `image` — one JPEG, PNG or WebP image, base64-encoded, at most 6 MiB decoded. The type is read from the image's leading bytes; a declared type is ignored.
  - `languages` — optional `front` and `back` BCP 47 tags, the deck's languages, passed to the model as hints.
- Success is `200` with `{ "cards": [{ "front", "back" }] }`: 1 to 100 cards, each side plain trimmed text of 1 to 500 characters (code points).
- Every refusal is `{ "error": "<code>" }`, the code naming the case the app shows:

| Status | Code | When |
|---|---|---|
| 400 | `bad_request` | the body is not JSON, has no base64 `image`, or has a malformed `languages` |
| 401 | `unauthenticated` | no bearer token, an invalid one, the anon key, or an anonymous sign-in |
| 405 | `method_not_allowed` | a method other than `POST` |
| 413 | `too_large` | the image is over 6 MiB decoded, or the body is larger than such an image could make it |
| 415 | `unsupported_type` | the image is not JPEG, PNG or WebP |
| 422 | `no_cards` | the model found no card on the page |
| 429 | `rate_limited` | the user has made 30 extractions today (UTC) |
| 502 | `model_error` | OpenRouter failed, or the output was invalid twice |
| 503 | `not_configured` | `OPENROUTER_API_KEY`, `CARD_MODEL`, or a platform variable is missing, or a model ID is malformed |

- A request is checked in this order: method, configuration, user, body, daily limit, model. A refused request never reaches the model or the count.
- `config.toml` sets `verify_jwt = true` for the function, so the platform refuses a request without a valid JWT first. The function then asks Supabase Auth for the token's user, which refuses the anon key, and refuses a user with `is_anonymous`.

### Model call

- OpenRouter chat completions, with the image as a data URL and `response_format` a strict JSON schema of the card list, generated from the same limits the parser enforces (`cards.ts`).
- `provider.require_parameters` routes only to providers that honour the schema; `max_tokens` is 16384.
- The prompt is `prompt_v1.ts`. A changed prompt is a new versioned file, so an eval result names the prompt it measured.
- The reply is parsed, not trusted: anything other than JSON of exactly the schema's shape, after trimming each side, is invalid output.
- Invalid output is retried once; a second invalid output is `502`. An HTTP or network failure is `502` without a retry.
- A valid empty list is `422`.

### Switching the model

- `CARD_MODEL` is the OpenRouter model ID of every first call. Changing the secret switches the model with no code change.
- `CARD_RETRY_MODEL`, when set, is the model of the retry, so a cheap model can fall back to a stronger one; unset, the retry uses `CARD_MODEL`.
- `OPENROUTER_API_KEY` is a Supabase secret. Locally it is in `supabase/functions/.env`, which git ignores; creating that file is an owner action.

### Privacy

- The image is sent to OpenRouter and nowhere else: it is not stored, not written to disk, and not logged.
- Each request logs one JSON line with exactly `user_id`, `model` (the last call's), `latency_ms`, `prompt_tokens`, `completion_tokens` (summed over the calls), and `outcome` (the response code, or `ok`).
- Nothing else is printed: not the cards, the token, or a configuration value. An unexpected failure logs its line with outcome `internal` and propagates to the runtime, which answers `500`.

### Daily limit

- 30 extractions per user per UTC day, counted in `public.extraction_usage` ([`server.md`](server.md)).
- The function records an extraction through `public.consume_extraction` with the service-role key, before calling the model, so a failed or empty extraction still counts.
- The count and its insert run under a per-user advisory lock, so two concurrent requests cannot both take the last extraction.

### Tests

- `supabase/functions/extract-cards/*_test.ts`, run by `make test` through `deno.sh`, with Supabase and OpenRouter replaced by a fake `fetch`: no network in CI.
- They cover authentication, size and type refusal, the schema and the one retry, the daily limit, the configuration, and the log line. They run without write or network permission, and a test asserts that, so a write anywhere fails the suite.
- The SQL side of the limit is tested by `supabase/tests/extraction_usage_test.sql`.

### Eval

- `tools/eval/run.ts` runs every configuration in `tools/eval/candidates.json` over every sample and writes `docs/eval/extract-cards.md`: per configuration, precision, recall, F1, p50 and p90 latency, cost per image, and total spend, then the recommendation.
- A candidate names patterns, not IDs. At run time each resolves to the newest model in OpenRouter's model list that matches, takes images, and supports structured outputs, and the report records the exact IDs and prices.
- Scores are per image, then averaged. A candidate card matches when both sides equal the ground truth after the card key normalization ([`deck.md`](deck.md)); an image with no cards scores 0.
- The recommendation is the cheapest configuration per image whose F1 is within 2 points of the best.
- Spend is capped at $10 across all runs, recorded in `tools/eval/spend.json`, which each run appends to.
  - A run starts only when a dry estimate fits the remaining budget; `--dry-run` prints the estimate and calls no model.
  - Before each image it checks that the worst case of a call and its retry still fits, and stops otherwise.
  - It prints the run's spend and the total after each run.
- The samples are `tools/eval/samples/`: 24 synthetic photos and their ground truth, written by `tools/eval/generate.py` from `tools/eval/vocabulary.json` and the OFL fonts in `tools/eval/fonts/`. Provenance and licences are in `tools/eval/samples/provenance.md`.
- The eval needs `supabase/functions/.env`, so it runs on the owner's machine, not in CI.

## Rationale

- [ADR 0013](adr/0013-extract-cards-function-and-eval.md) records the function's shape, the limit's mechanism, the retry model, and where the eval lives.
- Issue #25 records the contract, limits, privacy rule and eval method as decided by the PM.

## Open questions

- Which model `CARD_MODEL` names. The eval has not run: it waits for the owner's `supabase/functions/.env`, so `docs/eval/` holds no report yet.
- The samples are rendered pages, not phone photos. Real photos can be added to `tools/eval/samples/` with a ground-truth file each.
- `SUPABASE_SERVICE_ROLE_KEY` is Supabase's legacy key form. A project that disables legacy keys would need the function to read `SUPABASE_SECRET_KEYS` instead.
