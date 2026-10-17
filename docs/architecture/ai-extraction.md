# AI extraction

The `extract-cards` Edge Function that turns a photo of a study page, a vocabulary page or notes, into candidate cards, its limits and privacy, how its model is switched, the eval that chooses the model, and the app's `photo_import` domain that calls it.

## Current decisions

### Location

- The function is `supabase/functions/extract-cards/`, a Deno module with no third-party dependency: it calls Supabase Auth, PostgREST and OpenRouter with `fetch` ([ADR 0013](adr/0013-extract-cards-function-and-eval.md)).
- It reads the caller through `supabase/functions/_shared/auth.ts`, which the `delete-account` function shares ([ADR 0026](adr/0026-delete-the-account-through-an-edge-function.md)); a deploy bundles it.
- `index.ts` is its composition site: it reads the configuration once and passes `fetch`, the logger and the clock to the handler, which constructs none of them.
- The eval is `tools/eval/`, outside the function, so the deployed folder holds only the function. It imports the function's extraction module, so it measures the same prompt, schema and retry.
- Only the PM deploys the function and sets its secrets, after the pull request that changes it merges.

### Contract

- `POST` with the user's access token as `Authorization: Bearer`, and a JSON body:
  - `image` — one JPEG, PNG or WebP image, base64-encoded, at most 6 MiB decoded. The type is read from the image's leading bytes; a declared type is ignored.
  - `languages` — optional `front` and `back` BCP 47 tags, the deck's languages, passed to the model as hints.
- Success is `200` with `{ "cards": [...] }`, 1 to 100 cards, each text field plain trimmed text ([ADR 0051](adr/0051-extract-each-card-with-a-question-a-fullest-and-a-short-answer-and-a-detail-step-and-eval-notes-pages-by-terms.md)):
  - `kind` — `vocabulary` for an entry of a vocabulary list, glossary, bilingual table or dictionary page, `note` for a point of notes;
  - `front` — the headword or phrase as the page prints it, or, for a note, a question or the term the point defines, 1 to 500 characters (code points);
  - `answer` — the fullest answer the page supports: a vocabulary entry's meaning or meanings as printed, or a note's point in a sentence or a few, 1 to 1000 characters;
  - `short` — a shorter form of `answer`, no longer than it, 1 to 500 characters;
  - `step` — 1 to 5, the detail step from which the card is offered: 1 the page's core ideas, 5 every detail; every vocabulary entry is 1;
  - `examples` — present only when the page prints any for the card, 1 to 5 example sentences, phrases or worked examples of 1 to 500 characters each;
  - `meaning` — a vocabulary card's `answer`, for apps that read it ([ADR 0028](adr/0028-extract-each-card-in-fields-and-compose-its-answer-at-a-detail-level-in-the-app.md)); a note card has none;
  - `partOfSpeech` — on a vocabulary card, present only when the page prints one for the entry, its own notation verbatim, such as `[동]`, `n.` or `(형)`, 1 to 500 characters;
  - `back` — for apps that read only `front` and `back`: a vocabulary card's `partOfSpeech`, a space and `meaning`, or `meaning` alone, at most 1501 characters; a note card's `answer`.
- An app that has not updated reads a vocabulary card as before and a note card as its `front` and `back`, the fullest answer at every level: `app/lib/photo_import/src/extraction_client.dart` limits no field's length, ignores the keys it does not know, and takes `back` as the meaning when there is none.
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
- The schema asks for `kind`, `front`, `answer`, `short`, `step`, `partOfSpeech` and `examples` on every card, since strict structured outputs require every key: `kind` and `step` are enums, an absent part of speech is `null`, absent examples an empty list, and the parser turns both into an absent field.
- The prompt is `prompt_v3.ts` ([ADR 0051](adr/0051-extract-each-card-with-a-question-a-fullest-and-a-short-answer-and-a-detail-step-and-eval-notes-pages-by-terms.md)). A changed prompt is a new versioned file, so an eval result names the prompt it measured.
- Nothing is invented: the prompt asks for vocabulary exactly as written; for notes it lets the model phrase a question and join or shorten the page's words, and forbids any fact, meaning, part of speech or example the page does not show. A page's own worked example may be a card or a card's example. The eval measures how often a model invents anyway.
- The reply is parsed, not trusted: anything other than JSON of exactly the schema's shape, after trimming each field, is invalid output — a field empty once trimmed or over its limit, a step outside 1 to 5, an unknown kind, more than 5 examples, or more than 100 cards among it — and so is a `short` longer than its `answer`, or a note with a part of speech.
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
- They cover authentication, size and type refusal, each kind's fields and `back`, a note card without `meaning`, a missing part of speech, the steps and kinds, a short form longer than its answer, a note with a part of speech, the field limits, prompt v2's shape refused, the schema and the one retry, the daily limit, the configuration, and the log line. They run without write or network permission, and a test asserts that, so a write anywhere fails the suite.
- The SQL side of the limit is tested by `supabase/tests/extraction_usage_test.sql`.

### Eval

- `tools/eval/run.ts` runs every configuration in `tools/eval/candidates.json` over every sample and writes `docs/eval/extract-cards.md`: per configuration, for vocabulary pages precision, recall, F1, part-of-speech and examples precision and the invented rate; for notes pages coverage at each step, unsupported cards, invented examples and step order; p50 and p90 latency, cost per image, and total spend, then the recommendation ([ADR 0051](adr/0051-extract-each-card-with-a-question-a-fullest-and-a-short-answer-and-a-detail-step-and-eval-notes-pages-by-terms.md)).
- A candidate names patterns, not IDs. At run time each resolves to the newest model in OpenRouter's model list that matches, takes images, and supports structured outputs, and the report records the exact IDs and prices.
- `candidates.json` holds seven configurations: Claude Haiku, Sonnet and Opus 5.5, Haiku with a Sonnet retry, the newest Gemini Flash and Pro, and the newest GPT mini. The newest GPT left it on 2026-10-18 to fit the budget.
- Vocabulary pages: scores are per image, then averaged. A candidate card matches when its front and its `meaning`, or its `answer` when it has none, equal the ground truth after the card key normalization ([`deck.md`](deck.md)); an image with no cards scores 0.
- Over the matched cards of every vocabulary image:
  - part-of-speech precision is the share of returned parts of speech equal to the page's, and examples precision the share of returned examples the page prints, each after the same normalization;
  - the invented rate is the share of returned fields — a part of speech, or a card's examples — on an entry whose page prints no such field;
  - each is shown as a dash when the configuration returned no such field.
- Notes pages: a card covers a fact when its front and answer hold every one of the fact's terms after the same normalization.
  - Coverage at step s is the share of the page's facts of step s or below that a card of step s or below covers, per image and then averaged.
  - Unsupported cards are the share of returned cards that cover no fact, and invented examples the share of returned examples the page does not print; a returned example counts as printed when it and a printed one contain each other.
  - Step order is the share of pairs of covered facts with different steps that the returned steps order alike, a tie counting half; a covered fact's returned step is the lowest step of a card covering it.
  - Term matching undercounts a fact the model paraphrased past its terms, in coverage and as an unsupported card: the cost of scoring with no judge model.
- The recommendation is the cheapest configuration per image whose vocabulary F1 is within 2 points of the best and whose notes coverage at step 5 is within 5 points of the best; none when no configuration is within both.
- Spend is capped at $10 across all runs, recorded in `tools/eval/spend.json`, which each run appends to.
  - A run starts only when a dry estimate fits the remaining budget; `--dry-run` prints the estimate and calls no model. The estimate prices every image as a call and a retry, a vocabulary card's reply at 45 tokens and a note card's at 120. On 2026-10-18 it came to $7.82 for the 32 samples and seven configurations, with $10 remaining.
  - Before each image it checks that the worst case of a call and its retry still fits, and stops otherwise.
  - It prints the run's spend and the total after each run.
- The samples are `tools/eval/samples/`: 32 synthetic photos and their ground truth, written by `tools/eval/generate.py` from `tools/eval/vocabulary.json`, `tools/eval/notes.json` and the OFL fonts in `tools/eval/fonts/`. Provenance and licences are in `tools/eval/samples/provenance.md`.
- The 24 vocabulary pages: a ground-truth card holds `front` and `meaning`, and the `partOfSpeech` and `examples` its page prints: the six dictionary pages print a part of speech for every entry — `n.`, `v.`, `adj.` or `adv.` for English, a bracket notation such as `[동]` for Japanese — and an example under each English entry; the other layouts print neither.
- The 8 notes pages, `kind` "notes": a Korean page of logic notes and an English page of economics notes, each in a print and a handwriting face under the mild and the harsh distortion. A ground truth holds 12 facts, each with its `step` (every step from 1 to 5 has one) and the page `terms` that cover it, and the `examples` the page prints. None is a real photo; the owner's own notes photo was not used.
- The eval needs `supabase/functions/.env`, so it runs on the owner's machine, not in CI.

### App: the `photo_import` domain

- The app side is the domain `app/lib/photo_import/`; its public surface is `app/lib/photo_import/photo_import.dart`, with internals under `app/lib/photo_import/src/` ([`structure.md`](structure.md)). It exports:
  - `PhotoImportScreen`, and `photoImportProvider`, which builds it for a deck or for a new one, null while the app has no extraction client; the composition site overrides it with a builder over the client, and `home/`'s screens read it for their photo buttons ([`home.md`](home.md));
  - `ExtractionClient`, the seam to the function, `CandidateCard`, and `HttpExtractionClient`;
  - `DetailLevel`, and `detailLevelStorageKeys`, the key the device storage it is given must cache;
  - `PhotoSource` and `CameraSession`, the seam to the camera and the photo library, and `DevicePhotoSource`;
  - `JpegPhoto`, and the failures: `PhotoImportFailure` and its cases.
- It depends on `deck`'s surface for the decks, the card key and the import save. `deck` does not import it, and `home/` opens its screen.
- The screen receives its client, its photo source, and the device storage the detail level is kept in; it constructs none of them.
- The composition site, `app/lib/main.dart`, builds the client from the Supabase client `connectAccount` returns ([`account.md`](account.md)), without importing `supabase_flutter`:
  - the URL is `extractCardsUrl` of the client's public PostgREST URL, which swaps its `/rest/v1` suffix for `/functions/v1/extract-cards`, as the Supabase client builds both from the project URL;
  - the token is read from the client's current session at each request;
  - the device storage is the one `shared_preferences` store it opens for the theme ([`design.md`](design.md)), caching `themeStorageKeys` and `detailLevelStorageKeys`.
- A build with no Supabase client gets no extraction client, and `photoImportProvider` stays null, which hides both photo buttons.

#### Detail level

- How much each card's answer says, composed in the app from one extraction, so a switch is instant and never counts against the daily limit ([ADR 0028](adr/0028-extract-each-card-in-fields-and-compose-its-answer-at-a-detail-level-in-the-app.md)):

| Level | Answer |
|---|---|
| 간단 (Simple) | `meaning` |
| 기본 (Basic), the default | `partOfSpeech`, a space, then `meaning`; `meaning` alone when there is no part of speech |
| 자세히 (Detailed) | the 기본 answer, then each example on its own line |

- The web photo flow, when it is built, composes by the same rule.
- The choice is stored on the device with `shared_preferences`, as the theme is, read when the screen opens, and applied at once; 기본 when none is stored.
- Candidates combined on one card key take each candidate's answer at the current level, joined by `deck`'s merge-back rule.

#### Flow

- **Capture** — a full-screen camera view in the dark theme:
  - a page-frame guide, and the hint "단어장이나 책 한 페이지를 틀 안에 맞춰 찍어 주세요";
  - a top chip "추가할 덱 · <name>" that opens a sheet of every deck and "새 덱";
  - under it, "카드에 담을 내용" over a segmented control of 간단, 기본 and 자세히;
  - the album button bottom-left and the shutter in the centre.
- **Extracting** — the photo's thumbnail, "카드를 찾고 있어요", an indeterminate bar, skeleton rows, and "사진은 카드를 만드는 데만 쓰고 서버에 남기지 않아요":
  - "취소", or leaving the screen, aborts the request;
  - the skeleton rows shimmer, and hold still under reduce motion.
- **Review** — "카드 n개를 찾았어요" and "눌러서 고치고, 뺄 카드는 체크를 끄세요 · <deck>":
  - the same "카드에 담을 내용" control at the top; a switch recomposes every candidate's answer at once;
  - each candidate is a row with a checkbox and its front and back split by a divider, each centred vertically in its side;
  - a tap on a side edits it in place, and a side left empty keeps its previous text;
  - an answer typed by hand stays as typed through every switch, marked "직접 고침" under it;
  - candidates with one card key on the photo are combined into one before review, their backs joined by `deck`'s merge-back rule;
  - candidates whose key the deck holds are grouped below under "이미 있는 카드 n개", each with its own option chip: 건너뛰기 (the default), 뒷면 합치기 or 새 카드로 추가 ([`deck.md`](deck.md));
  - "다시 찍기" at the top right returns to the camera;
  - "카드 n개 추가" counts the checked candidates not set to skip, and is disabled at 0.
- **Saving** — one `DeckRepository.importCards` call, each answer as the review shows it, plain text as every import writes. For a new deck, the name sheet asks for its name first. The screen then pops with the deck saved into, and the home and deck screens open that deck's screen.
- Nothing is written before "카드 n개 추가": not the deck, not a card.

#### Photo

- The camera is `camera`'s back camera without audio, released while the app is out of the foreground and opened again when it returns, after a refusal too, so access allowed in Settings takes effect. One open runs at a time, and a lifecycle change during one is applied when it lands. The library is `image_picker`'s picker, asked for at most 2048 px per side, without full metadata so no photo-library permission is needed.
- Every photo is decoded, turned upright by its EXIF orientation, scaled so its long side is at most 2048 px keeping its aspect ratio, and encoded as JPEG at quality 85, stepping down to 40 until it is at most 6 MiB. This runs on a background isolate with the pure-Dart `image` package.
- A file `image` cannot decode, such as a HEIC photo, is `PhotoUnreadable`.

#### Request and failures

- `HttpExtractionClient` posts `{"image": <base64 JPEG>}` to `<SUPABASE_URL>/functions/v1/extract-cards` with the session's access token as `Authorization: Bearer`, through `package:http` with an abortable request. Without a session it sends nothing.
- The answer is parsed at the boundary: a `200` must hold a non-empty `cards` list, each card a non-empty `front` and `back`, and a non-empty `meaning`, `partOfSpeech` and list of non-empty `examples` where present. A card without `meaning`, from a function deployed before the fields, takes `back` as its meaning, so every level shows that `back`.
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

- `app/test/photo_import/photo_import_screen_test.dart` drives the screen with a substitute photo source and extraction client, and device storage in memory (`app/test/photo_import/fakes.dart`), over an in-memory database: the deck chip, cancel, edits, exclusions, the three duplicate options, the saved count, each failure, the camera across a lifecycle change or a departure during an open, reduce motion, nothing written before adding, the default level, each level as shown, saved and remembered, a switch on review keeping a typed answer marked edited, combined candidates at a level, and the accessibility guidelines in both themes.
- `app/test/photo_import/extraction_client_test.dart` runs `HttpExtractionClient` over `package:http`'s `MockClient`: the request, the fields, an answer without them, each status, malformed answers, offline, no session, and abort; and `extractCardsUrl` over project URLs with a trailing slash and a path prefix.
- `app/test/widget_test.dart` composes the app with and without an extraction client and checks that the photo button follows.
- `app/test/photo_import/photo_test.dart` checks the downscaling: aspect ratio, long side, size limit and orientation.
- `app/test/photo_import/permissions_test.dart` reads `Info.plist`, both `InfoPlist.strings`, the Xcode project and the Android manifest.
- No test or CI job calls the deployed function.

## Rationale

- [ADR 0013](adr/0013-extract-cards-function-and-eval.md) records the function's shape, the limit's mechanism, the retry model, and where the eval lives.
- [ADR 0028](adr/0028-extract-each-card-in-fields-and-compose-its-answer-at-a-detail-level-in-the-app.md) records why one extraction returns each card's fields and the app composes the answer, why `back` stays, and why prompt v1 was removed.
- [ADR 0051](adr/0051-extract-each-card-with-a-question-a-fullest-and-a-short-answer-and-a-detail-step-and-eval-notes-pages-by-terms.md) records the notes cards, the fullest and short answers and the detail step, why `back` stays readable, prompt v3, the notes samples and metrics, and why the eval scores notes by terms rather than a judge model; issue #148 records the owner's request.
- Issue #73 records the fields, the no-invention rule, the three levels and where the user chooses them, as decided by the PM on 2026-10-15.
- Issue #25 records the contract, limits, privacy rule and eval method as decided by the PM, and issue #30 the app flow, its errors and its screens.

## Open questions

- On Android, the system may end the app while the photo picker is open; the picked photo is then lost and the user picks again. `image_picker`'s `retrieveLostData` could recover it.
- Which model `CARD_MODEL` names, how well each covers a notes page's facts step by step, and how often each invents a fact, a part of speech or an example. The eval has not run, with any prompt: it waits for the owner's run on their machine, so `docs/eval/` holds no report yet.
- The samples are rendered pages, not phone photos. Real photos can be added to `tools/eval/samples/` with a ground-truth file each.
- `SUPABASE_SERVICE_ROLE_KEY` is Supabase's legacy key form. A project that disables legacy keys would need the function to read `SUPABASE_SECRET_KEYS` instead.
