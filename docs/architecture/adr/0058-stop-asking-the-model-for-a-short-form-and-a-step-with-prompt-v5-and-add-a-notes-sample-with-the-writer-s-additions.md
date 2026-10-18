# ADR 0058: Stop asking the model for a short form and a step with prompt v5, and add a notes sample with the writer's additions

> Status: accepted; its prompt v5 and its cap order superseded by ADR-0063
> Date: 2026-10-18

Append-only: once merged, the body below is not rewritten. A fact later found wrong is corrected in an appended note, not edited out; a revised decision is a new ADR that supersedes this one.

## Context

- Issue #189 records the owner's choice of 2026-10-18: Claude Sonnet 5.5 for every photo, since on real notes pages it alone caught handwritten annotations. It asks to cut Sonnet's cost per photo without losing that.
- **Evidence.** The PM's eval runs of 2026-10-18 measured prompt v4 as merged in #179. They ran on four notes pages: samples 27, 33 and 35, plus the owner's own photo of a textbook page, kept only locally.
  - Sonnet covered 88.8 of the facts, at $0.0367 per image.
  - On the owner's page it used 6796 prompt and 2037 completion tokens, about $0.014 of input and $0.020 of output.
  - Output is the larger share, and it is what a prompt can shrink.
- **Fields nobody reads.** Prompt v4 asks every card for `short`, a shorter form of the answer, and `step`, the detail step from which it is offered ([ADR 0051](0051-extract-each-card-with-a-question-a-fullest-and-a-short-answer-and-a-detail-step-and-eval-notes-pages-by-terms.md), [ADR 0055](0055-cover-everything-a-notes-page-teaches-at-step-5-with-prompt-v4-and-eval-a-dense-page-by-coverage-per-page.md)). Only the five-step slider read them ([ADR 0052](0052-choose-a-photo-s-cards-and-how-full-their-answers-are-on-a-five-step-slider-in-the-app.md)), and [ADR 0057](0057-group-a-photo-s-cards-by-topic-on-review-with-a-switch-per-topic-and-swipes-per-card.md) removes the slider. Each card writes its answer twice over when `short` restates it.
- **The app on `main`.** `app/lib/photo_import/src/extraction_client.dart` refuses a card that has a `kind` but no `step` from 1 to 5 and a non-empty `short`. The app change that drops the slider, #187, merges first, but an installed app may predate it.
- **The eval.** It scored notes per step and by step order. With no step from the model, every card would sit at one step: coverage at steps 1 to 4 would only restate coverage at step 5, and step order would only count ties.
- **The owner's page.** It has a structure no committed sample has:
  - a classification table;
  - a definition section with printed examples;
  - the owner's additions by hand: a starred list to memorise, numbered judgment methods, and a rule written beside a heading.
  - The cards the owner expects from it are the definition, the starred list as one card, a table row's list as one card, and both judgment methods as one card.
  - The photo itself is never committed.
- Alternatives considered:
  - **Keeping `short` and `step` and asking for them more tersely.** The model would still write two fields the new app ignores.
  - **Dropping both from the response too.** The app on `main` would refuse every card until #187 reaches every device.
  - **Running v4 and v5 side by side in the eval**, for a comparison in one run. It would keep v4's prompt and schema in the code only to measure them. The PM chose to compare v5's run with the v4 table in #189, on the same samples.
  - **Copying the owner's page.** The PM ruled that a sample models its structure, not its content.

## Decision

- **Prompt v5.**
  - `prompt_v5.ts` replaces `prompt_v4.ts`, which nothing imports any more and git keeps.
  - It asks for no `short` and no `step`, and the schema drops both.
  - Every other rule of v4 stands. That includes the theory-first card, its `topic`, worked examples only on their rule's card, and the rules against invention.
- **The 100-card cap.** With no step to drop last, a page over the cap keeps its definitions, rules and marked exceptions before its minor list members, in the page's order.
- **The response stays readable.**
  - The parser fills every card's `short` with its `answer` and its `step` with 1, so the app on `main` reads each card at every slider step, with its full answer.
  - Every other field of the response is unchanged.
  - A reply that still carries `short` or `step` is invalid output, since the schema is strict.
- **The eval scores one coverage.**
  - A notes page's coverage is the share of its facts that some card covers, through the card's front and answer as before. It equals coverage at step 5 in reports before v5.
  - The report's notes table gives coverage, unsupported cards and invented examples, and drops the per-step columns and step order.
  - Its per-page section is "Coverage per notes page", with the completion tokens of each page's calls.
  - The recommendation's notes bound reads that coverage.
  - The samples' facts keep their `step`, which no metric reads.
- **A sample with the writer's additions.** `ko-auxiliary` in `tools/eval/notes.json` is a Korean grammar page on 보조 용언, written for the project on the structure of the owner's page. `generate.py` draws it in both hands and both distortions as samples 37 to 40, and samples 01 to 36 stay byte-identical.
  - It holds a ruled classification table, the definition with printed examples, and blue-pen additions in the handwriting face on every page: a starred list, two numbered judgment methods, and a spacing rule beside its heading.
  - Its truth makes each list one fact: the starred list's four members, a table row's four auxiliary verbs, and both judgment methods.
- **Measuring it.**
  - The PM runs v5 with Sonnet over samples 27, 33 and 35, the owner's photo kept locally, and samples 37 to 40.
  - The PM compares cost per image, completion tokens and coverage with #189's v4 table.
- **Supersessions.**
  - This replaces ADR 0055's prompt v4, its cap rule by step, and its report of coverage at step 5 per step.
  - It also replaces ADR 0051's `short` and `step` written by the model, and its notes scoring by step and step order.

## Consequences

- Each card's reply loses its short form and its step, so a photo costs fewer completion tokens on every model. By how much is unmeasured until the PM's run.
- Until #187 reaches a device, its slider offers every card at every step and shows the full answer at 핵심.
- The eval can no longer tell whether a model places a fact at the right step. No prompt asks for steps now.
- The report's notes numbers before and after v5 compare only through coverage at step 5, which this report calls coverage.

## Signs the decision was wrong

- Sonnet's coverage on the PM's run of v5 falls below v4's on the same pages, so the dropped fields were helping the model organise the page.
- Completion tokens per image barely fall, so the cost lies elsewhere, such as in hidden reasoning.
- Users of an app before #187 report that its slider no longer changes anything, often enough to matter before they update.
- A later decision brings back a slider or steps, which would need a prompt that asks for them again.
