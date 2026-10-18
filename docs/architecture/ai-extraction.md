# AI extraction

The `extract-cards` Edge Function that turns a photo of a study page, a vocabulary page or notes, into candidate cards, its limits and privacy, how its model is switched, the eval that chooses the model, and the app's `photo_import` domain that calls it.

## Current decisions

### Location

- The function is `supabase/functions/extract-cards/`, a Deno module with no third-party dependency: it calls Supabase Auth, PostgREST and OpenRouter with `fetch` ([ADR 0013](adr/0013-extract-cards-function-and-eval.md)).
- It reads the caller through `supabase/functions/_shared/auth.ts`, which the `delete-account` function shares ([ADR 0026](adr/0026-delete-the-account-through-an-edge-function.md)); a deploy bundles it.
- `index.ts` is its composition site: it reads the configuration once and passes `fetch`, the logger and the clock to the handler, which constructs none of them.
- The eval is `tools/eval/`, outside the function, so the deployed folder holds only the function. It imports the function's extraction module, so it measures the same prompt, schema and retry.
- Merging the pull request that changes the function deploys it, through Supabase's GitHub integration; a change needing a new secret or changing the model or the cost of a call merges only after the owner approves it ([`server.md`](server.md) §Edge Function deploys).
- Its secrets are set by hand on the production project, by the owner or the PM only; a merge sets none.

### Contract

- `POST` with the user's access token as `Authorization: Bearer`, and a JSON body:
  - `image` — one JPEG, PNG or WebP image, base64-encoded, at most 6 MiB decoded. The type is read from the image's leading bytes; a declared type is ignored.
  - `languages` — optional `front` and `back` BCP 47 tags, the deck's languages, passed to the model as hints.
- Success is `200` with `{ "cards": [...] }`, 1 to 100 cards, each text field plain trimmed text ([ADR 0051](adr/0051-extract-each-card-with-a-question-a-fullest-and-a-short-answer-and-a-detail-step-and-eval-notes-pages-by-terms.md)):
  - `kind` — `vocabulary` for an entry of a vocabulary list, glossary, bilingual table or dictionary page, `note` for a point of notes;
  - `front` — the headword or phrase as the page prints it, or, for a note, the name of the concept, rule or exception it states, never a question, 1 to 500 characters (code points);
  - `answer` — the fullest answer the page supports: a vocabulary entry's meaning or meanings as printed, or a note's theory, the definition, rule or exception, in a sentence or a few, 1 to 1000 characters;
  - `short` — the `answer` again, and `step` — 1, for an app that offers cards by step on a slider ([ADR 0052](adr/0052-choose-a-photo-s-cards-and-how-full-their-answers-are-on-a-five-step-slider-in-the-app.md)); the model writes neither, and the function fills both ([ADR 0058](adr/0058-stop-asking-the-model-for-a-short-form-and-a-step-with-prompt-v5-and-add-a-notes-sample-with-the-writer-s-additions.md));
  - `topic` — the name of the page section the card comes from, its heading without numbering, or the page's title where it has no headings, 1 to 60 characters; cards of one section share it, so an app can group them by it ([ADR 0055](adr/0055-cover-everything-a-notes-page-teaches-at-step-5-with-prompt-v4-and-eval-a-dense-page-by-coverage-per-page.md));
  - `examples` — present only when the page prints any for the card, 1 to 5 example sentences, phrases or worked examples of 1 to 500 characters each; a note's worked examples are those the page prints for its rule;
  - `meaning` — a vocabulary card's `answer`, for apps that read it ([ADR 0028](adr/0028-extract-each-card-in-fields-and-compose-its-answer-at-a-detail-level-in-the-app.md)); a note card has none;
  - `partOfSpeech` — on a vocabulary card, present only when the page prints one for the entry, its own notation verbatim, such as `[동]`, `n.` or `(형)`, 1 to 500 characters;
  - `back` — for apps that read only `front` and `back`: a vocabulary card's `partOfSpeech`, a space and `meaning`, or `meaning` alone, at most 1501 characters; a note card's `answer`.
- An app that has not updated reads a vocabulary card as before and a note card as its `front` and `back`, ignoring `topic`, the fullest answer at every level: its parser, `app/lib/photo_import/src/extraction_client.dart` as released before topics, limits no field's length, ignores the keys it does not know, and takes `back` as the meaning when there is none. Today's parser refuses a `topic` over 60 characters.
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
- The schema asks for `kind`, `front`, `answer`, `topic`, `partOfSpeech` and `examples` on every card, and for no `short` or `step`, since strict structured outputs require every key: `kind` is an enum, an absent part of speech is `null`, absent examples an empty list, and the parser turns both into an absent field.
- The prompt is `prompt_v5.ts` ([ADR 0058](adr/0058-stop-asking-the-model-for-a-short-form-and-a-step-with-prompt-v5-and-add-a-notes-sample-with-the-writer-s-additions.md)), prompt v4 ([ADR 0055](adr/0055-cover-everything-a-notes-page-teaches-at-step-5-with-prompt-v4-and-eval-a-dense-page-by-coverage-per-page.md)) without its short form and step. A changed prompt is a new versioned file, so an eval result names the prompt it measured. Merging a change to the function deploys it (#177), so a prompt change reaches users on merge.
- For notes, cards hold the theory and the exceptions: a card for every definition, rule, list member and marked exception, each on its own card. A card states the theory rather than asking a question: its front names the concept, such as "광합성" or "ㄷ 불규칙 (듣다)", and its answer is the theory. A worked example is never a card of its own; it is an example of the card whose rule it illustrates, and only when the page prints it. No separate rules merged, no rule or exception left out as minor, and at most 100 cards, a page over the cap keeping its definitions, rules and marked exceptions before its minor list members.
- Nothing is invented: the prompt asks for vocabulary exactly as written; for notes it lets the model name a concept and join or shorten the page's words, and forbids any fact, meaning, part of speech or example the page does not show. The eval measures how often a model invents anyway.
- The reply is parsed, not trusted: anything other than JSON of exactly the schema's shape, after trimming each field, is invalid output — a field empty once trimmed or over its limit, a topic over 60 characters, a key outside the schema such as v4's `short` or `step`, an unknown kind, more than 5 examples, or more than 100 cards among it — and so is a note with a part of speech.
- Invalid output is retried once; a second invalid output is `502`. An HTTP or network failure is `502` without a retry.
- A valid empty list is `422`.

### Switching the model

- `CARD_MODEL` is the OpenRouter model ID of every first call. Changing the secret switches the model with no code change.
- `CARD_RETRY_MODEL`, when set, is the model of the retry, so a cheap model can fall back to a stronger one; unset, the retry uses `CARD_MODEL`.
- On 2026-10-18 the owner first chose Claude Sonnet 5.5 from the notes report, and the PM set `CARD_MODEL` to `anthropic/claude-sonnet-5.5`; `CARD_RETRY_MODEL` already named it (issue #184).
- Later that day the owner judged the dense grammar page a deliberate worst case and moved back to Claude Haiku 5.5. The PM set `CARD_MODEL` to `anthropic/claude-haiku-5.5` at 2026-10-18T04:56:22Z, with `CARD_RETRY_MODEL` still on Sonnet. The evidence was a run over the 24 vocabulary pages: Haiku F1 99.0 at $0.0009 per image, Sonnet F1 100.0 at $0.0161, and neither invented a field (`docs/eval/extract-cards.md`).
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
- They cover authentication, size and type refusal, each kind's fields and `back`, a note card without `meaning`, a missing part of speech, the kinds, the short form and step the function fills, a note with a part of speech, the field limits, prompt v2's shape refused, the prompt's request to cover a notes page exhaustively while inventing nothing, the schema and the one retry, the daily limit, the configuration, and the log line. They run without write or network permission, and a test asserts that, so a write anywhere fails the suite.
- The SQL side of the limit is tested by `supabase/tests/extraction_usage_test.sql`.

### Eval

- `tools/eval/run.ts` runs every configuration in `tools/eval/candidates.json` over every sample and writes `docs/eval/extract-cards.md`: per configuration, for vocabulary pages precision, recall, F1, part-of-speech and examples precision and the invented rate; for notes pages coverage, unsupported cards and invented examples, and each notes page's coverage with the completion tokens its calls used against `max_tokens`; p50 and p90 latency, cost per image, and total spend, then the recommendation ([ADR 0051](adr/0051-extract-each-card-with-a-question-a-fullest-and-a-short-answer-and-a-detail-step-and-eval-notes-pages-by-terms.md)).
- A candidate names patterns, not IDs. At run time each resolves to the newest model in OpenRouter's model list that matches, takes images, and supports structured outputs, and the report records the exact IDs and prices.
- `candidates.json` holds eight configurations ([ADR 0059](adr/0059-keep-one-sonnet-call-per-photo-after-measuring-an-outline-then-fill-pipeline-and-the-newest-models.md)): Claude Haiku and Sonnet 5.5; Claude Opus 5.5 and Fable 5.1 as ceilings, the most a model reaches on the samples; Haiku with a Sonnet retry; the newest Gemini, by the name `gemini-<version>-argon`; and the newest OpenAI GPT Sol and Luna, by the names `gpt-<version>-sol` and `gpt-<version>-luna`. On 2026-10-18 OpenRouter's list showed those names for OpenAI's newest models, the earlier `-mini` matching only `gpt-5.4-mini`, and Gemini's 3.x Pro only as a preview, so the former Pro pattern resolved to nothing. `openai/gpt-6-astra`, at Fable's price, is left out.
- Vocabulary pages: scores are per image, then averaged. A candidate card matches when its front and its `meaning`, or its `answer` when it has none, equal the ground truth after the card key normalization ([`deck.md`](deck.md)); an image with no cards scores 0.
- Over the matched cards of every vocabulary image:
  - part-of-speech precision is the share of returned parts of speech equal to the page's, and examples precision the share of returned examples the page prints, each after the same normalization;
  - the invented rate is the share of returned fields — a part of speech, or a card's examples — on an entry whose page prints no such field;
  - each is shown as a dash when the configuration returned no such field.
- Notes pages: a page's facts are its rules and exceptions, each holding the worked examples the page prints for it; a worked example is not a fact. A card covers a fact when its front and answer hold every one of the fact's terms after the same normalization; its examples do not count, since another rule's worked example can hold a rule's terms ([ADR 0055](adr/0055-cover-everything-a-notes-page-teaches-at-step-5-with-prompt-v4-and-eval-a-dense-page-by-coverage-per-page.md)).
  - Coverage is the share of the page's facts that some card covers, per image and then averaged. It equals coverage at step 5 in reports before prompt v5, whose cards carry no step of their own; the facts keep their `step`, which no metric reads ([ADR 0058](adr/0058-stop-asking-the-model-for-a-short-form-and-a-step-with-prompt-v5-and-add-a-notes-sample-with-the-writer-s-additions.md)).
  - Unsupported cards are the share of returned cards that cover no fact, and invented examples the share of returned examples the page does not print. A returned example counts as printed when it and one of the page's worked examples contain each other, or when a line the page prints contains it, as a rule's own worked example sits in the rule's line.
  - Term matching undercounts a fact the model paraphrased past its terms, in coverage and as an unsupported card: the cost of scoring with no judge model.
- The recommendation is the cheapest configuration per image whose vocabulary F1 is within 2 points of the best and whose notes coverage is within 5 points of the best; none when no configuration is within both.
- Spend is capped at $10 across all runs, recorded in `tools/eval/spend.json`, which each run appends to.
  - A run starts only when a dry estimate fits the remaining budget; `--dry-run` prints the estimate and calls no model. The estimate prices every image as a call and a retry, a vocabulary card's reply at 45 tokens and a note card's at 120. On 2026-10-18 it came to $9.81 for the 36 samples and seven configurations, with $10 remaining; v4's exhaustive replies may run longer than its 120 tokens a fact.
  - Before each image it checks that the worst case of a call and its retry still fits, and stops otherwise.
  - A call's spend is the cost OpenRouter reports. A call that reports no usage, which a failed call does, records none: OpenRouter's key usage shows the 2026-10-18 run's failed calls were not billed (issue #184).
  - A candidate whose calls fail two images in a row runs no further image, and the report says how many it ran. OpenRouter's model list cannot exclude such a candidate before the run: it lists `structured_outputs` for Gemini Flash, which Google refused on every call (below).
  - After the calls it prints the run's spend and the total, writes the report, then appends the run to the ledger, the ledger even when the report's write fails. A failed write therefore loses at most one of them, and the printed spend survives both.
  - A write creates its directory only when the directory is missing, so the grant in `run.ts`'s header command, `tools/eval/spend.json` and `docs/eval`, covers every write; the grant also names `tools/eval/replies`. Issue #180 records the 2026-10-18 run, which failed with `NotCapable` on its first write after every call had completed.
  - A run whose spend never reached the ledger is entered by hand: append `{ "date": "YYYY-MM-DD", "spentUsd": <cost>, "note": "<source>" }` to `runs` in `tools/eval/spend.json`, with the cost OpenRouter's activity page shows for the run's calls and a note naming that page. The PM enters the 2026-10-18 run this way.
- Every reply is kept as each image completes, in `tools/eval/replies/<UTC start>/<configuration>/<sample>.json`, which git ignores, and the report names the folder. A reply holds the outcome, the parsed cards, and each call's model with its HTTP status and body, or the error that ended it.
- The 2026-10-18 run's report, prompt v4 as it stood at `47569b2d226d124fc3ea23f52f027c9b134c1d96`, before the theory-first revision, over the 12 notes pages, is `docs/eval/extract-cards.md`, and its spend is in the ledger as OpenRouter's key usage shows it (issue #184). The report's spend lines are the eval's pricing at the time, and it notes the correction.
  - Its invented-examples rates of 61–83% counted a rule's worked example, printed in the rule's line, as invented, since the ground truth then listed only the examples on lines of their own. Sonnet's kept replies on the four grammar pages hold 81 examples: 63 counted as invented then, and 1 under the rule above, a misread of "졸졸" as "촐촐" on a harsh page.
  - Google Gemini Flash (`google/gemini-3.8-flash`) failed every call. Its kept replies show Google answering `400 INVALID_ARGUMENT`, "Request contains an invalid argument.", through both providers OpenRouter tried, Google AI Studio and Google Vertex, so it is not routing; the answer names no argument.
- #191's runs of 2026-10-18, Claude Sonnet 5.5 over samples 27, 33, 35 and 37 to 40, by the PM: prompt v4 covered 75.5 with 27.0 unsupported and 6.5 invented examples at $0.0271 per image; prompt v5 covered 78.2 with 22.7 unsupported and 0.0 invented at $0.0229, about 15% cheaper. The owner's photo was not among them.
- The PM's further runs of 2026-10-18 on prompt v5, over samples 27, 33, 35 and 37 to 40 (`docs/eval/extract-cards.md`), decided that a photo stays one Claude Sonnet 5.5 call ([ADR 0059](adr/0059-keep-one-sonnet-call-per-photo-after-measuring-an-outline-then-fill-pipeline-and-the-newest-models.md)):
  - an outline on Sonnet with the cards filled by Claude Haiku 5.5 (#192, removed after the run) covered 72.3 at $0.0179 per image and a p50 of 16.9 s, against Sonnet alone's 78.2 at $0.0229 and 9.2 s; its outline call alone cost $0.0158;
  - OpenAI GPT 6.1 Sol covered 75.5 at $0.0227 and 29.3 s, with 7.5 invented examples, and GPT 6 Luna 67.3 at $0.0016 and 24.9 s;
  - Google Gemini 4 Argon failed both calls with Google's `400 INVALID_ARGUMENT`, unbilled.
- The samples are `tools/eval/samples/`: 40 synthetic photos and their ground truth, written by `tools/eval/generate.py` from `tools/eval/vocabulary.json`, `tools/eval/notes.json` and the OFL fonts in `tools/eval/fonts/`. Provenance and licences are in `tools/eval/samples/provenance.md`.
- The 24 vocabulary pages: a ground-truth card holds `front` and `meaning`, and the `partOfSpeech` and `examples` its page prints: the six dictionary pages print a part of speech for every entry — `n.`, `v.`, `adj.` or `adv.` for English, a bracket notation such as `[동]` for Japanese — and an example under each English entry; the other layouts print neither.
- The 16 notes pages, `kind` "notes": a Korean page of logic notes, an English page of economics notes, a dense Korean grammar page, and a Korean grammar page with the writer's additions, each in a print and a handwriting face under the mild and the harsh distortion.
  - A ground truth holds the page's rules and exceptions as facts, each with its `step`, the page `terms` that cover it and the worked `examples` the page prints for it, and its `lines`, every line it prints. Every step from 1 to 4 has a fact on every page.
  - The logic and economics pages hold 10 facts each. The grammar page, `ko-grammar`, drawn at four-fifths size, holds 21: many small rules, and exceptions marked with a drawn star or circle, with its worked examples on their rules.
  - The page with the writer's additions, `ko-auxiliary`, samples 37 to 40, follows the structure of the owner's textbook page, not its content (issue #189). It holds a ruled table classifying 용언, the definition of 보조 용언 with printed examples, and additions in blue pen in the handwriting face: a starred list, two numbered judgment methods, and a spacing rule beside its heading. Its 9 facts make each list one card: the starred list, a table row's verbs, and both judgment methods.
  - None is a real photo; the owner's own photos were not used.
- The eval needs `supabase/functions/.env`, so it runs on the owner's machine, not in CI.
- `tools/eval/*_test.ts`, run by `make test` through `deno.sh`, test the eval with OpenRouter replaced by a fake `fetch`. `run_test.ts` substitutes the file system too. `run_io_test.ts` runs the eval through `denoIo`, its real I/O, as a subprocess under the header command's permission flags, with only `fetch` replaced (`run_fake_openrouter.ts`). `deno.sh` runs it apart from the other tests, with write access only to a temporary directory it removes, and permission to run `deno`.

### App: the `photo_import` domain

- The app side is the domain `app/lib/photo_import/`; its public surface is `app/lib/photo_import/photo_import.dart`, with internals under `app/lib/photo_import/src/` ([`structure.md`](structure.md)). It exports:
  - `importFromPhoto`, which starts an import over a context and resolves to the deck saved into, and `photoImportProvider`, which provides it as a `PhotoImport` for a deck or for a new one, null while the app has no extraction client; the composition site overrides it with a function over the client, and `home/`'s screens read it for their photo buttons ([`home.md`](home.md));
  - `ExtractionClient`, the seam to the function, `CandidateCard`, and `HttpExtractionClient`;
  - `photoImportStorageKeys`, the keys the device storage it is given must cache;
  - `PhotoSource`, the seam to the system camera, the photo library and the app's settings page, and `DevicePhotoSource`;
  - `JpegPhoto`, and the failures: `PhotoImportFailure` and its cases.
- It depends on `deck`'s surface for the decks, the card key and the import save. `deck` does not import it, and `home/` opens its screen.
- The import receives its client, its photo source, and the device storage that keeps whether Review's coach has shown; it constructs none of them.
- The composition site, `app/lib/main.dart`, builds the client from the Supabase client `connectAccount` returns ([`account.md`](account.md)), without importing `supabase_flutter`:
  - the URL is `extractCardsUrl` of the client's public PostgREST URL, which swaps its `/rest/v1` suffix for `/functions/v1/extract-cards`, as the Supabase client builds both from the project URL;
  - the token is read from the client's current session at each request;
  - the device storage is the one `shared_preferences` store it opens for the theme ([`design.md`](design.md)), caching `themeStorageKeys` and `photoImportStorageKeys`.
- A build with no Supabase client gets no extraction client, and `photoImportProvider` stays null, which hides both photo buttons.

#### Topics

- Review groups the cards by the `topic` each carries, keeps or drops a topic with its switch and a card with a swipe, and shows no slider ([ADR 0057](adr/0057-group-a-photo-s-cards-by-topic-on-review-with-a-switch-per-topic-and-swipes-per-card.md)).
- The answer a card shows and saves is the part of speech the page prints, a space, then its answer; its answer alone when the page prints none, as for every note.
- The function writes a topic on every card (Contract above). A card without one, from a function deployed before topics, goes into one section with no heading and no switch.
- The app no longer reads a card's `step` or `short`, which the function keeps for apps that have not updated ([ADR 0052](adr/0052-choose-a-photo-s-cards-and-how-full-their-answers-are-on-a-five-step-slider-in-the-app.md)'s slider, offering, composition and storage are superseded in the app). A device keeps a step stored under `photoDetailStep`, unread.
- The web has no photo import; one built later groups by the same rule.

#### Flow

- **Source** — the photo button opens the sheet "사진 가져오기" over the screen it is on, with "사진 찍기", the system camera, and "앨범에서 고르기", the library ([ADR 0054](adr/0054-take-the-photo-with-the-system-camera-or-from-the-library-and-remove-the-in-app-camera-view.md)):
  - the photo import screen opens only with a photo, at Extracting, or with the failure that came instead of one;
  - a sheet dismissed or a picker cancelled opens nothing and shows no error.
- **Extracting** — the photo's thumbnail, "카드를 찾고 있어요", an indeterminate bar, skeleton rows, and "사진은 카드를 만드는 데만 쓰고 서버에 남기지 않아요":
  - "취소" aborts the request and closes the screen, as leaving it does;
  - the skeleton rows shimmer, and hold still under reduce motion.
- **무엇을 외울까요** ([ADR 0060](adr/0060-choose-which-topics-to-memorise-and-their-card-shape-before-review-from-the-one-call-s-cards.md)) — "카드 n장을 만들었어요." then "무엇을 외울까요?", n the cards Review shows when every topic is on: each topic's cards in its shape, those of one card key counted once, as Review combines them. "닫기" at the top left closes the screen:
  - one pill per topic, in the order each first appears, on at first with a check, toggled by a tap; cards with no topic go under "이 페이지";
  - for each topic that is on, its first card as a sample, in the topic's shape: a tap on its front offers "개념 이름" (the default) or "내용을 앞에", which puts the content in front and the concept's name behind; a tap on its back offers "핵심만" (the default, the answer) or "예시까지", the answer and then each example the page prints on its own line, offered only when a card of the topic has examples. Each option is a choice chip, read as selected or not. The shape applies to every card of the topic, with no call, and stays when the topic's pill goes off and on;
  - no pill takes a typed topic: one call cannot make cards for it;
  - "다음" opens Review with the cards of the topics that are on, each in its topic's shape, and is disabled when none is on. The deck's card keys are read then, and a failure to read them shows in a snack bar and stays on "무엇을 외울까요".
- **Review** — "카드 n장을 만들었어요", n the cards passed from "무엇을 외울까요", those of one card key counted once, then the chip "추가할 덱 · <name>" that opens a sheet of every deck and "새 덱":
  - the cards are grouped by topic, in the order each first appears; a section's heading is "<topic> · n장" with a switch, on at first. Off, every card of the topic shows as removed, its heading is muted, and its cards cannot be edited; on again, each card not removed on its own comes back;
  - each card shows its front and its answer side by side, each breaking lines only between words through `keepWords` ([`design.md`](design.md)), and a screen reader hears it as written with what a tap and a swipe do;
  - a swipe left removes a card and a swipe right puts it back, the directions of studying's "모른다" and "안다" ([`study.md`](study.md)), with "빼기" on the red or "다시 넣기" on the green under the moving card; a removed card stays listed, struck through inside a dashed outline. A card whose topic is off takes no swipe;
  - a tap opens a card for editing in place: "앞면" and "뒷면" fields, "이 카드 빼기" or "다시 넣기", and "완료". What is typed is kept, a side left empty keeping its text, whether the edit ends by "완료", by the remove or restore button, by a tap on another card, by a switch, or by adding the cards;
  - a screen reader opens a card with a tap and removes or puts it back with the custom action "빼기" or "다시 넣기"; a card whose topic is off has neither;
  - candidates with one card key on the photo are combined into one before review, their answers joined by `deck`'s merge-back rule;
  - a card whose key the deck holds shows "이미 덱에 있어요" under it and starts removed; choosing another deck decides again which cards start removed, for each card the user has not removed, put back or edited. An edit whose front the deck holds keeps the card as it was, marked, and it merges back when saved;
  - on first use, a three-step coach shows a finger on the first card and dims the others, with "왼쪽으로 밀면 빼요", "오른쪽으로 밀면 다시 넣어요" and "눌러서 바로 고쳐요", dots, "건너뛰기" and "다음", the last "시작하기", in place of the add button. It is stored as shown under `photoReviewCoachShown` when it first shows, any swipe, tap or switch ends it, and it does not show under reduce motion;
  - the back at the top left, and a system back, return to "무엇을 외울까요" with its pills and shapes as they were; Review's own changes are not kept, and "다음" builds it again;
  - "다시 찍기" at the top right opens the source sheet over the review; a cancel keeps the review, and a photo replaces it;
  - "덱에 n장 추가" counts the cards whose topic is on and which are not removed, and is disabled at 0.
- **Saving** — one `DeckRepository.importCards` call over the cards kept, each answer as the review shows it, plain text as every import writes; each merges back into a card with its key, so a duplicate put back adds its answer to the deck's card. For a new deck, the name sheet asks for its name first. The screen then pops with the deck saved into, and the home and deck screens open that deck's screen.
- Nothing is written before "덱에 n장 추가": not the deck, not a card.

#### Photo

- The camera and the library are `image_picker`'s system camera and picker, each asked for at most 2048 px per side, without full metadata so the library needs no photo-library permission. The settings page is iOS's `app-settings:` address, opened through `url_launcher`.
- Every photo is decoded, turned upright by its EXIF orientation, scaled so its long side is at most 2048 px keeping its aspect ratio, and encoded as JPEG at quality 85, stepping down to 40 until it is at most 6 MiB. This runs on a background isolate with the pure-Dart `image` package.
- A file `image` cannot decode, such as a HEIC photo, is `PhotoUnreadable`.

#### Request and failures

- `HttpExtractionClient` posts `{"image": <base64 JPEG>}` to `<SUPABASE_URL>/functions/v1/extract-cards` with the session's access token as `Authorization: Bearer`, through `package:http` with an abortable request. Without a session it sends nothing.
- The answer is parsed at the boundary: a `200` must hold a non-empty `cards` list, each card a non-empty `front` and `back`, and a non-empty `answer`, `meaning`, `partOfSpeech`, `topic` and list of non-empty `examples` where present, the topic at most 60 characters.
  - A card's answer is its `answer`, else its `meaning`, else its `back`, so a function deployed before the fields still reads.
  - The app reads no other field.
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
| `PhotoAccessDenied` | camera or photo access is refused or restricted | retake, "설정 열기"; a snack bar when the settings page does not open |
| `CameraUnavailable` | the device has no camera | retake, where the album still works |

- A `DeckFailure` while reading the deck or saving is shown in a snack bar, as the deck screens show one; `DeckDeleted` says the deck was deleted meanwhile.

#### Permissions

- `app/ios/Runner/Info.plist` holds `NSCameraUsageDescription` and `NSPhotoLibraryUsageDescription` in English, and `app/ios/Runner/ko.lproj/InfoPlist.strings` and `en.lproj/InfoPlist.strings` hold them in Korean and English. It holds no microphone description: the system camera takes photos without sound.
- `app/android/app/src/main/AndroidManifest.xml` declares neither `CAMERA` nor `RECORD_AUDIO`. `image_picker` asks for the camera permission only when the manifest declares it, so its camera intent and photo picker ask for none, and Android never reports a refusal.

#### App tests

- `app/test/photo_import/photo_import_screen_test.dart` drives the screen with a substitute photo source and extraction client, and device storage in memory (`app/test/photo_import/fakes.dart`), over an in-memory database: the source sheet, each source, a cancel of the sheet, the camera or the album, a refused permission with its way to Settings, a device without a camera, cancel while extracting, the skeleton under reduce motion; on the choice screen the headline and pills, the headline counting cards of one key once as Review does, a pill switched off and on with its effect on Review and with its shape kept, "다음" disabled with no topic on, "내용을 앞에" and "예시까지" on the sample and on Review, each alone and together, "예시까지" offered only for a topic with examples, the default option read as selected, a deck that cannot be read on "다음", the back and the system back from Review keeping the choices, and cards with no topic under "이 페이지"; on Review the topics with their counts and switches, cards without a topic, a swipe each way against a short drag, a topic switched off and on, editing in place with its remove and restore button, only the cards kept saved, a duplicate that starts removed and merges back, combined candidates, the deck chip and the duplicates it decides again, a new deck named on saving, a retake cancelled or taken, each side breaking lines only between words as a screen reader hears the card; the coach's three steps, its end by a gesture or Skip, its flag, and its absence once shown or under reduce motion; each failure; and the accessibility guidelines in both themes. It starts each import from a button, as the home and deck screens do.
- `app/test/photo_import/extraction_client_test.dart` runs `HttpExtractionClient` over `package:http`'s `MockClient`: the request, the answer from `answer`, `meaning` or `back` with the part of speech, the topic and the examples and their absence, the fields no longer read, each status, malformed answers, offline, no session, and abort; and `extractCardsUrl` over project URLs with a trailing slash and a path prefix.
- `app/test/widget_test.dart` composes the app with and without an extraction client and checks that the photo button follows.
- `app/test/photo_import/photo_test.dart` checks the downscaling: aspect ratio, long side, size limit and orientation.
- `app/test/photo_import/permissions_test.dart` reads `Info.plist`, both `InfoPlist.strings`, the Xcode project and the Android manifest: the camera and library descriptions present, the microphone's absent, and no camera or microphone permission on Android.
- No test or CI job calls the deployed function.

## Rationale

- [ADR 0013](adr/0013-extract-cards-function-and-eval.md) records the function's shape, the limit's mechanism, the retry model, and where the eval lives.
- [ADR 0028](adr/0028-extract-each-card-in-fields-and-compose-its-answer-at-a-detail-level-in-the-app.md) records why one extraction returns each card's fields and the app composes the answer, why `back` stays, and why prompt v1 was removed.
- [ADR 0051](adr/0051-extract-each-card-with-a-question-a-fullest-and-a-short-answer-and-a-detail-step-and-eval-notes-pages-by-terms.md) records the notes cards, the fullest and short answers and the detail step, why `back` stays readable, prompt v3, the notes samples and metrics, and why the eval scores notes by terms rather than a judge model; issue #148 records the owner's request.
- [ADR 0052](adr/0052-choose-a-photo-s-cards-and-how-full-their-answers-are-on-a-five-step-slider-in-the-app.md), superseded in the app by ADR 0057, records the five-step slider, which rows each step offers and how full their answers are, why a hidden row is not saved, the reading of the old response, and why a stored level maps to a step.
- [ADR 0054](adr/0054-take-the-photo-with-the-system-camera-or-from-the-library-and-remove-the-in-app-camera-view.md) records the system camera and the library in place of the in-app camera view, why the source sheet comes before the screen, the deck chip on review, the refusal and its way to Settings, why Android declares no camera permission, and the black screen's cause; issue #174 records the owner's report and choice.
- [ADR 0055](adr/0055-cover-everything-a-notes-page-teaches-at-step-5-with-prompt-v4-and-eval-a-dense-page-by-coverage-per-page.md) records prompt v4's coverage of every rule and exception at step 5, the theory-first card with its `topic`, worked examples only on their rule's card, the dense page, coverage of rules and exceptions through a card's front and answer, the per-page report, the measured limits and the proposal for `max_tokens`; issue #176 records the owner's request, and #179 the owner's decisions of 2026-10-18.
- [ADR 0057](adr/0057-group-a-photo-s-cards-by-topic-on-review-with-a-switch-per-topic-and-swipes-per-card.md) records the cards grouped by topic on Review, the switches and swipes that replace the slider and the checkboxes, the coach, and why a survey and a choice screen were dropped; issue #182 records the owner's request.
- [ADR 0058](adr/0058-stop-asking-the-model-for-a-short-form-and-a-step-with-prompt-v5-and-add-a-notes-sample-with-the-writer-s-additions.md) records prompt v5 without the short form and step, the function filling both for the app, the eval's single coverage, and the sample with the writer's additions; issue #189 records the owner's aim and the PM's v4 measurements.
- [ADR 0059](adr/0059-keep-one-sonnet-call-per-photo-after-measuring-an-outline-then-fill-pipeline-and-the-newest-models.md) records the outline-then-fill and newest-model measurements, why a photo stays one Sonnet call, why the outline code was removed, and the candidates' patterns; issue #189 records the aim.
- [ADR 0060](adr/0060-choose-which-topics-to-memorise-and-their-card-shape-before-review-from-the-one-call-s-cards.md) records the choice screen before Review, built from the one call's topics, the shapes a topic takes, why there is no typed topic, and the headline, the label for cards with no topic and the examples read again; issue #190 records the owner's request.
- Issue #73 records the fields, the no-invention rule, the three levels and where the user chooses them, as decided by the PM on 2026-10-15.
- Issue #25 records the contract, limits, privacy rule and eval method as decided by the PM, and issue #30 the app flow, its errors and its screens.

## Open questions

- On Android, the system may end the app while the photo picker is open; the picked photo is then lost and the user picks again. `image_picker`'s `retrieveLostData` could recover it.
- Whether one call can cover a dense page within `max_tokens` of 16384: the proposal in ADR 0055 raises it to 32768 if a dense page uses more than 12,000 completion tokens in a call or fails twice.
- On samples 37 to 40, whether a prompt can keep the writer's numbered judgment methods as one card and a table row's verbs in its answer: under v4 and v5 alike, Sonnet wrote the methods as two cards and the verbs as examples (#191's runs, coverage 66.7 on each).
- How well each model names topics, and how often it invents a fact, a part of speech or an example: the only notes report, of 2026-10-18, measured v4 before its theory-first revision.
- Which argument Google refuses in our request. Every Gemini model tried fails with it: Gemini Flash (`google/gemini-3.8-flash`) and Gemini 4 Argon with `400 INVALID_ARGUMENT`, unbilled, and Gemini 2.5 Pro with two model errors that stopped it (#189).
- The samples are rendered pages, not phone photos. Real photos can be added to `tools/eval/samples/` with a ground-truth file each.
- `SUPABASE_SERVICE_ROLE_KEY` is Supabase's legacy key form. A project that disables legacy keys would need the function to read `SUPABASE_SECRET_KEYS` instead.
