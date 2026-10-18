# ADR 0051: Extract each card with a question, a fullest and a short answer, and a detail step, and eval notes pages by their terms

> Status: accepted; its prompt v3, its note card's question-shaped front, and its worked-example facts on the notes pages, superseded by ADR-0055; its short form and detail step written by the model, and its notes scoring by step and step order, superseded by ADR-0058
> Date: 2026-10-18

Append-only: once merged, the body below is not rewritten. A fact later found wrong is corrected in an appended note, not edited out; a revised decision is a new ADR that supersedes this one.

## Context

- Issue #148 records the owner's request of 2026-10-17: photo import reads any study page, handwritten lecture notes included and not only a word–meaning list, and turns what is worth memorising into question–answer cards. A five-step slider, from 핵심 to 세부, sets both which cards are offered and how full their answers are, without another model call or extraction from the daily limit.
- On `main` at `2eba4f90674736714c20b908fea05922a8d125b5`, `extract-cards` reads a vocabulary page into `front`, `meaning`, `partOfSpeech` and `examples`, with a composed `back`, under prompt v2 ([ADR 0028](0028-extract-each-card-in-fields-and-compose-its-answer-at-a-detail-level-in-the-app.md)). The eval scores vocabulary pages alone, matching each card on front and meaning ([ADR 0013](0013-extract-cards-function-and-eval.md)).
- The PM's direction in the issue: one call returns, for each card, a question or headword, the answer at its fullest, a shorter form, and the step from 1 to 5 at which it first appears; a vocabulary page keeps its fields. The AI may phrase a question, but every fact and example in an answer comes from the page, and the eval measures that as it measures invented fields today. The issue splits the work: this part covers the function, the prompt and the eval; the app's slider follows.
- The PM confirmed the shape and the measures on 2026-10-18, on the worker's question in the dispatch of part 1, and approved a dry run that makes only OpenRouter's keyless model-list request.
- An app that has not updated parses each card on `main` (`app/lib/photo_import/src/extraction_client.dart`) as a non-empty `front` and `back`, with the optional `meaning`, `partOfSpeech` and `examples`; it limits no field's length, ignores keys it does not know, and takes `back` as the meaning when there is none.
- Scoring notes needs to tell whether a card states a fact of the page. A judge model would cost a call per card and fall outside the eval's spend cap; matching the page's own terms costs nothing and repeats exactly.
- Alternatives considered:
  - Two calls, one per page type, or a call per slider step. Each costs more extractions against the daily limit of 30, and a step switch could not be free.
  - Only `answer` and `step`, with the app shortening the answer itself. The app cannot shorten a sentence faithfully without a model.
  - Dropping `back`. An app that has not updated would then refuse every card.

## Decision

- **Model reply.** The schema asks for every card's `kind` (`vocabulary` or `note`), `front` (the headword, or a question or the term a point defines), `answer` (the fullest answer the page supports), `short` (a shorter form, no longer than `answer`), `step` (an integer from 1 to 5), `partOfSpeech` (a string or `null`) and `examples` (at most 5). `answer` is at most 1000 code points and every other text field at most 500. Beyond the schema, the parser refuses a `short` longer than its `answer` and a note with a part of speech; either is invalid output and takes the one retry.
- **Steps.** A card is offered from its step upward: step 1 holds the page's core ideas and step 5 every detail. Every vocabulary entry is step 1, so on a vocabulary page the slider changes only how full the answers are.
- **Response.** Each card is `{kind, front, answer, short, step, back}` with `examples` when the page prints any. A vocabulary card also carries `meaning`, equal to its `answer`, and `partOfSpeech` when printed; its `back` is `partOfSpeech`, a space and `meaning`, as before, now at most 1501 code points. A note card carries no `meaning`, and its `back` is its `answer`, at most 1000 code points. So an app that has not updated shows a vocabulary card as it does today, and a note card's fullest answer at every level.
- **Prompt.** `prompt_v3.ts` replaces `prompt_v2.ts`, which nothing imports once the schema changed; git keeps it. It asks for vocabulary verbatim as before, lets the model phrase a note's question and join or shorten the page's words, and forbids any fact, meaning, part of speech or example the page does not show; a page's own worked example may be a card or a card's example.
- **Eval samples.** Eight synthetic notes pages join the 24 vocabulary pages: a Korean page of logic notes and an English page of economics notes, from `tools/eval/notes.json`, each in a print and a handwriting face and under the mild and the harsh distortion. A notes ground truth holds the page's facts, each with its step and the terms a card's front and answer must all hold to cover it, and the examples the page prints.
- **Eval metrics.** A vocabulary card is matched on its front and its `meaning`, or its `answer` when it has none. For notes, per image and then averaged:
  - coverage at each step: the share of facts of that step or below covered by a card of that step or below;
  - unsupported cards: the share of returned cards that cover no fact;
  - invented examples: the share of returned examples the page does not print, a returned example counting as printed when it and a printed one contain each other after normalization, since a card may keep or drop the page's "예)" label;
  - step order: the share of pairs of covered facts with different steps that the returned steps order alike, a tie counting half.
  - Term matching undercounts a fact the model paraphrased past its terms, both in coverage and as an unsupported card; that is the cost of having no judge model.
- **Recommendation.** The cheapest configuration per image whose vocabulary F1 is within 2 points of the best and whose notes coverage at step 5 is within 5 points of the best; none when no configuration is within both.
- **Dry run.** The estimate prices a note card's reply at 120 tokens and a vocabulary card's at 45. Run on 2026-10-18 over the 32 samples, the eight candidates came to $12.06, above the $10 budget. On the PM's decision, OpenAI's newest GPT, the costliest at $4.23, left `candidates.json`, with Opus 5.5 remaining as the high-quality reference, bringing the run to $7.82.
- **Supersessions.** This replaces ADR 0028's model reply, response, prompt v2 and the eval's matching on `meaning` alone, and ADR 0013's eval of vocabulary pages alone and its recommendation on F1 alone. ADR 0028's app composition, its three levels and their storage stand until the slider replaces them.

## Consequences

- One extraction carries what every slider step needs, so a step switch can stay free and instant once the app reads it.
- An app that has not updated keeps working against the new function, and shows a note card's fullest answer on its back; the new app will need the new function, which the PM deploys after the owner picks a model.
- A card's reply is about twice as long as under v2 for vocabulary and longer still for notes, so a call costs more completion tokens.
- The notes scores lean on the terms chosen for each fact: a fact whose terms a model would rephrase scores low for a correct card.
- The eval's results stay unmeasured until the owner runs it on their machine with `supabase/functions/.env`.

## Signs the decision was wrong

- Every candidate's unsupported rate is high on cards a reader would call correct, so term matching misjudges paraphrase too often to rank models.
- Step order agreement is near chance for every candidate, so one call cannot place cards on the slider reliably.
- Users move the slider and find step 1 holding details or step 5 adding nothing, so five steps are more than a page carries.
- The new app is deployed before the function and a note page fails, or an old app's users report notes cards with answers too long to read.

## Errata

- 2026-10-18: §Consequences says the new app will need the new function, "which the PM deploys after the owner picks a model". Supabase's GitHub integration deploys a changed function when its pull request merges into `main`, so no deploy follows the merge. #169 merged as `5ab5440e4475237dc21f25911a4d9f52ab89c3a1` at 19:20:11Z on 2026-10-17, and its `Supabase Preview` check on that commit ran 19:20:38–19:20:47Z. On 2026-10-18, `supabase functions list` showed `extract-cards` at version 9, updated 19:20:46 UTC, and no one had deployed it by hand (issue #177). Supabase's GitHub integration guide (`supabase/supabase` commit `626f0d412a5f88ef260289d4ed2b787f9705d6fc`, committed 2026-10-14, read 2026-10-18) lists "Edge Functions declared in `config.toml` are deployed" among the changes deployed to production. So #169's merge deployed prompt v3 with the `CARD_MODEL` already set. The decision stands. Picking a model is setting `CARD_MODEL`, which the owner or the PM does by hand on the production project, and a change to the model called waits for the owner's approval before merge ([`server.md`](../server.md) §Edge Function deploys).
