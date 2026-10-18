# ADR 0055: Cover everything a notes page teaches at step 5 with prompt v4, and eval a dense page by its coverage per page

> Status: accepted
> Date: 2026-10-18

Append-only: once merged, the body below is not rewritten. A fact later found wrong is corrected in an appended note, not edited out; a revised decision is a new ADR that supersedes this one.

## Context

- Issue #176 records the owner's report of 2026-10-18. On the device, a photo of a dense handwritten Korean grammar page (모음조화, 어미 아/어, 축약 and 탈락 rules, many worked examples, marked exceptions) gave 10 cards at the default step, where the page holds far more. The owner asked for the cards to cover everything on the page to memorise.
- On `main` at `a54c6d26f0a717ef7edccef19cd50a8d80335fe8`, prompt v3 ([ADR 0051](0051-extract-each-card-with-a-question-a-fullest-and-a-short-answer-and-a-detail-step-and-eval-notes-pages-by-terms.md)) asks for "one card per point worth memorising" and leaves the model to judge what is worth it.
- The eval's notes pages, a logic page and an economics page, teach 12 facts each, two of them worked examples. A card covers a fact only through its front and answer, although prompt v3 lets a worked example be the example of the card it illustrates.
- Issue #177 records that merging a change to `extract-cards` deploys it within a minute, so a prompt change reaches users on merge.
- **Measurement of the limits, without a model call.**
  - The dense page added below holds 25 lines of content and 24 worked examples, such as "보+아라 -> 봐라". Even if every line and every worked example became its own card, that is 49 cards, under the 100-card cap.
  - Those 49 cards, written as the schema asks with `short` as long as `answer`, are 10,276 bytes of UTF-8 JSON.
  - A tokenizer that falls back to bytes writes at most one token per byte, so the reply stays under about 10,300 tokens. That is under `max_tokens` of 16384, but it leaves about 6,000 tokens for a model's hidden reasoning, which counts against the same cap.
- Alternatives considered:
  - A call per step, or a second call for step 5 alone. Each costs another extraction against the daily limit, and a slider move could no longer be free ([ADR 0052](0052-choose-a-photo-s-cards-and-how-full-their-answers-are-on-a-five-step-slider-in-the-app.md)).
  - Raising `max_tokens` now. Nothing measured shows a page reaching the cap, and a higher cap raises the eval's worst-case guard on every call.

## Decision

- **Prompt v4.** `prompt_v4.ts` replaces `prompt_v3.ts`; nothing imports v3 any more, and git keeps it. For notes, v4 asks the model to cover everything the page teaches, in the page's order, so that studying every card memorises the page:
  - every definition and every rule, each on its own card;
  - each member of a list or table the page teaches, on its own card, or on one card when the page teaches the list as one item to recall;
  - each worked example, as its own card or as an example of the card whose rule it illustrates;
  - each exception, and each line the writer marked as important (a star, a circle, an underline, "※" or "!"), on its own card;
  - no merging of separate rules into one card, and no point left out for seeming minor: it goes to a higher step instead.
- **Steps and invention.** Every step keeps its meaning from ADR 0051, and step 5 offers every card. The rules against inventing a fact, a meaning, a part of speech or an example stand unchanged. The prompt's own examples are not taken from any eval page.
- **Cap.** At most 100 cards. On a page with more, the model keeps every card of steps 1 to 4 and leaves out the last cards of step 5.
- **Coverage.** A card covers a fact when its front, answer and examples together hold every one of the fact's terms. So a worked example kept as the example of its rule's card counts as covered, just as it would as a card of its own. This replaces ADR 0051's front and answer alone, in coverage and in the unsupported rate.
- **Dense page.** The eval's notes ground truth gains `ko-grammar` in `tools/eval/notes.json`: a Korean grammar page in the style of the owner's, written for the project.
  - It holds 30 lines in five sections, with 26 facts across every step: each rule, each vowel group, each contraction rule, each worked-example line, and each exception marked with a drawn star or circle.
  - `tools/eval/generate.py` draws it at four-fifths of the usual size, with the marks in red, in print and handwriting under both distortions. That is samples 33 to 36, and samples 01 to 32 stay byte-identical.
- **Per-page report.** The report gains a table of each notes page's coverage at step 5 for every configuration, beside the completion tokens its calls used against `max_tokens`.
- **Limit proposal.** Keep the 100-card cap and `max_tokens` of 16384 until the comparison run reports dense-page completion tokens. If any dense page uses more than 12,000 completion tokens in a call, or fails as invalid output twice, the next change raises `max_tokens` to 32768.
- **Before merge.** Run the comparison before this pull request merges, since the merge deploys v4. The dry run on 2026-10-18 estimated $9.8132 for the 36 samples and seven configurations, with $10 remaining. Its notes estimate counts a card per fact at 120 tokens; v4's exhaustive replies may run longer, and the run's per-image guard stops before the budget would be exceeded.
- **Supersessions.** This replaces ADR 0051's prompt v3, and its coverage and unsupported cards counted on a card's front and answer alone.

## Consequences

- A dense notes page gives many more cards at step 5, and the lower steps stay subsets of it, each holding what its step describes.
- Replies on notes pages grow longer, so a call costs more completion tokens and takes longer.
- The eval can now show whether a model covers a dense page at step 5, page by page, and whether its reply approaches the output cap.
- Coverage on the two earlier notes pages can rise for the same reply, since examples now count. No eval has run yet, so no published number changes.
- Merging deploys v4 to every user at once. An unmeasured regression reaches users unless the comparison runs first.

## Signs the decision was wrong

- Step-5 coverage on the dense page stays well below the earlier pages for every configuration, so a prompt alone cannot make one call exhaustive.
- The unsupported rate or invented examples rise under v4, as the push to cover everything turns into filler or examples the page does not print.
- Users find the lower steps crowded with details after v4, so "a higher step instead" does not hold.
- A dense page's reply is cut off at `max_tokens`, as invalid output twice or completion tokens near 16384.
