# AI extraction

The `extract-cards` Edge Function that turns a photo of a vocabulary page into candidate cards, its limits and privacy, how its model is switched, the eval that chooses the model, and the app's `photo_import` domain that calls it.

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

### App: the `photo_import` domain

- The app side is the domain `app/lib/photo_import/`; its public surface is `app/lib/photo_import/photo_import.dart`, with internals under `app/lib/photo_import/src/` ([`structure.md`](structure.md)). It exports:
  - `PhotoImportScreen`, the screen `deck`'s `photoImportProvider` builds;
  - `ExtractionClient`, the seam to the function, `CandidateCard`, and `HttpExtractionClient`;
  - `PhotoSource` and `CameraSession`, the seam to the camera and the photo library, and `DevicePhotoSource`;
  - `JpegPhoto`, and the failures: `PhotoImportFailure` and its cases.
- It depends on `deck`'s surface for the decks, the card key and the import save. `deck` does not import it.
- The screen receives its client and photo source; it constructs neither.
- The composition site, `app/lib/main.dart`, builds the client from the Supabase client `connectAccount` returns ([`account.md`](account.md)), without importing `supabase_flutter`:
  - the URL is `extractCardsUrl` of the client's public PostgREST URL, which swaps its `/rest/v1` suffix for `/functions/v1/extract-cards`, as the Supabase client builds both from the project URL;
  - the token is read from the client's current session at each request.
- A build with no Supabase client gets no extraction client, and `photoImportProvider` stays null, which hides both photo buttons.

#### Flow

- **Capture** — a full-screen camera view in the dark theme:
  - a page-frame guide, and the hint "단어장이나 책 한 페이지를 틀 안에 맞춰 찍어 주세요";
  - a top chip "추가할 덱 · <name>" that opens a sheet of every deck and "새 덱";
  - the album button bottom-left and the shutter in the centre.
- **Extracting** — the photo's thumbnail, "카드를 찾고 있어요", an indeterminate bar, skeleton rows, and "사진은 카드를 만드는 데만 쓰고 서버에 남기지 않아요":
  - "취소", or leaving the screen, aborts the request;
  - the skeleton rows shimmer, and hold still under reduce motion.
- **Review** — "카드 n개를 찾았어요" and "눌러서 고치고, 뺄 카드는 체크를 끄세요 · <deck>":
  - each candidate is a row with a checkbox and its front and back split by a divider;
  - a tap on a side edits it in place, and a side left empty keeps its previous text;
  - candidates with one card key on the photo are combined into one before review, their backs joined by `deck`'s merge-back rule;
  - candidates whose key the deck holds are grouped below under "이미 있는 카드 n개", each with its own option chip: 건너뛰기 (the default), 뒷면 합치기 or 새 카드로 추가 ([`deck.md`](deck.md));
  - "다시 찍기" at the top right returns to the camera;
  - "카드 n개 추가" counts the checked candidates not set to skip, and is disabled at 0.
- **Saving** — one `DeckRepository.importCards` call. For a new deck, the name dialog asks for its name first. The screen then pops with the deck saved into, and the deck screens open that deck's card list.
- Nothing is written before "카드 n개 추가": not the deck, not a card.

#### Photo

- The camera is `camera`'s back camera without audio, released while the app is in the background. The library is `image_picker`'s picker, asked for at most 2048 px per side, without full metadata so no photo-library permission is needed.
- Every photo is decoded, turned upright by its EXIF orientation, scaled so its long side is at most 2048 px keeping its aspect ratio, and encoded as JPEG at quality 85, stepping down to 40 until it is at most 6 MiB. This runs on a background isolate with the pure-Dart `image` package.
- A file `image` cannot decode, such as a HEIC photo, is `PhotoUnreadable`.

#### Request and failures

- `HttpExtractionClient` posts `{"image": <base64 JPEG>}` to `<SUPABASE_URL>/functions/v1/extract-cards` with the session's access token as `Authorization: Bearer`, through `package:http` with an abortable request. Without a session it sends nothing.
- The answer is parsed at the boundary: a `200` must hold a non-empty `cards` list of two non-empty sides each.
- Each failure is a `PhotoImportFailure`, shown in place of the screen with its ARB message:

| Failure | When | Offers |
|---|---|---|
| `ExtractionOffline` | the request could not reach the server | retry, retake |
| `PhotoRefused` | `413` or `415` | retake |
| `NoCardsFound` | `422` | retake |
| `DailyLimitReached` | `429` | close |
| `ModelFailed` | `502` | retry, retake |
| `SignInRequired` | `401`, or no session | close |
| `ServiceFailed` | any other status, or a `200` outside the contract | retry, retake |
| `PhotoUnreadable` | the photo cannot be decoded | retake |
| `CameraDenied`, `CameraUnavailable` | the camera is refused or missing | shown in place of the preview; the album still works |

- A `DeckFailure` while reading the deck or saving is shown in a snack bar, as the deck screens show one; `DeckDeleted` says the deck was deleted meanwhile.

#### Permissions

- `app/ios/Runner/Info.plist` holds `NSCameraUsageDescription`, `NSPhotoLibraryUsageDescription` and `NSMicrophoneUsageDescription` in English, and `app/ios/Runner/ko.lproj/InfoPlist.strings` and `en.lproj/InfoPlist.strings` hold them in Korean and English. The microphone key is there because `camera`'s setup asks for it; the app never opens audio.
- `app/android/app/src/main/AndroidManifest.xml` declares `CAMERA` and removes the `RECORD_AUDIO` that `camera_android_camerax` merges in.

#### App tests

- `app/test/photo_import/photo_import_screen_test.dart` drives the screen with a substitute photo source and extraction client (`app/test/photo_import/fakes.dart`) over an in-memory database: the deck chip, cancel, edits, exclusions, the three duplicate options, the saved count, each failure, reduce motion, nothing written before adding, and the accessibility guidelines in both themes.
- `app/test/photo_import/extraction_client_test.dart` runs `HttpExtractionClient` over `package:http`'s `MockClient`: the request, each status, malformed answers, offline, no session, and abort; and `extractCardsUrl` over project URLs with a trailing slash and a path prefix.
- `app/test/widget_test.dart` composes the app with and without an extraction client and checks that the photo button follows.
- `app/test/photo_import/photo_test.dart` checks the downscaling: aspect ratio, long side, size limit and orientation.
- `app/test/photo_import/permissions_test.dart` reads `Info.plist`, both `InfoPlist.strings`, the Xcode project and the Android manifest.
- No test or CI job calls the deployed function.

## Rationale

- [ADR 0013](adr/0013-extract-cards-function-and-eval.md) records the function's shape, the limit's mechanism, the retry model, and where the eval lives.
- Issue #25 records the contract, limits, privacy rule and eval method as decided by the PM, and issue #30 the app flow, its errors and its screens.

## Open questions

- On Android, the system may end the app while the photo picker is open; the picked photo is then lost and the user picks again. `image_picker`'s `retrieveLostData` could recover it.
- Which model `CARD_MODEL` names. The eval has not run: it waits for the owner's `supabase/functions/.env`, so `docs/eval/` holds no report yet.
- The samples are rendered pages, not phone photos. Real photos can be added to `tools/eval/samples/` with a ground-truth file each.
- `SUPABASE_SERVICE_ROLE_KEY` is Supabase's legacy key form. A project that disables legacy keys would need the function to read `SUPABASE_SECRET_KEYS` instead.
