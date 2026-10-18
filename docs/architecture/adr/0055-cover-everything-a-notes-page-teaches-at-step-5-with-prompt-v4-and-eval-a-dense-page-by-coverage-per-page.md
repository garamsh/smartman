# ADR 0055: Cover everything a notes page teaches at step 5 with prompt v4, and eval a dense page by its coverage per page

> Status: accepted
> Date: 2026-10-18

Append-only: once merged, the body below is not rewritten. A fact later found wrong is corrected in an appended note, not edited out; a revised decision is a new ADR that supersedes this one.

## Context

- Issue #176 records the owner's report of 2026-10-18. On the device, a photo of a dense handwritten Korean grammar page (모음조화, 어미 아/어, 축약 and 탈락 rules, many worked examples, marked exceptions) gave 10 cards at the default step, where the page holds far more. The owner asked for the cards to cover everything on the page to memorise.
- On `main` at `a54c6d26f0a717ef7edccef19cd50a8d80335fe8`, prompt v3 ([ADR 0051](0051-extract-each-card-with-a-question-a-fullest-and-a-short-answer-and-a-detail-step-and-eval-notes-pages-by-terms.md)) asks for "one card per point worth memorising" and leaves the model to judge what is worth it.
- The eval's notes pages, a logic page and an economics page, teach 12 facts each, two of them worked examples. A card covers a fact only through its front and answer, although prompt v3 lets a worked example be the example of the card it illustrates.
- Issue #177 records that merging a change to `extract-cards` deploys it within a minute, so a prompt change reaches users on merge.
- **The owner's decisions of 2026-10-18**, on #179 after reading the cards made from their own grammar notes:
  - What a learner memorises from such a page is the theory, its rules, and the special cases, its exceptions. A worked example such as "가 + 아라 = 가라" is a problem, not a thing to memorise: it is never a card of its own, only an example on the card of the rule it illustrates, and only when the page prints it.
  - A card states the theory and is not a quiz. Its front is the concept's name, such as "양성모음", "ㅗ + ㅏ 축약" or "여 불규칙 (하다)", and its back is the theory. Nothing is phrased as a question, such as "양성모음은?".
  - The eval's coverage counts rules and exceptions only. The dense page's worked examples move out of its facts, into the examples of their rule's fact.
- ADR 0057, in #183 for issue #182, builds a Review that groups a photo's cards by topic, and is built against a `topic` of 1 to 60 characters on each card, which this ADR adds to the function.
- Issue #184 found, from kept replies, that a rule's worked example printed inside the rule's line counted as an invented example, since the ground truth listed only examples on lines of their own; #185 adds every printed line to the notes truth.
- **Measurement of the limits, without a model call.**
  - The dense page added below holds 25 lines of content and 24 worked examples, such as "보+아라 -> 봐라". Even if every line and every worked example became its own card, that is 49 cards, under the 100-card cap.
  - Those 49 cards, written as the schema asks with `short` as long as `answer`, are 10,276 bytes of UTF-8 JSON.
  - A tokenizer that falls back to bytes writes at most one token per byte, so the reply stays under about 10,300 tokens. That is under `max_tokens` of 16384, but it leaves about 6,000 tokens for a model's hidden reasoning, which counts against the same cap.
- Alternatives considered:
  - A call per step, or a second call for step 5 alone. Each costs another extraction against the daily limit, and a slider move could no longer be free ([ADR 0052](0052-choose-a-photo-s-cards-and-how-full-their-answers-are-on-a-five-step-slider-in-the-app.md)).
  - Raising `max_tokens` now. Nothing measured shows a page reaching the cap, and a higher cap raises the eval's worst-case guard on every call.

## Decision

- **Prompt v4.** `prompt_v4.ts` replaces `prompt_v3.ts`; nothing imports v3 any more, and git keeps it. For notes, v4 asks for the theory and the exceptions, in the page's order, so that studying every card memorises what the page teaches:
  - every definition and every rule, each on its own card;
  - each member of a list or table the page teaches, on its own card, or on one card when the page teaches the list as one item to recall;
  - each exception, and each line the writer marked as important (a star, a circle, an underline, "※" or "!"), on its own card;
  - a worked example never as a card of its own: it goes in the examples of the card whose rule it illustrates, exactly as printed, and only when the page prints it;
  - no merging of separate rules into one card, and no rule or exception left out for seeming minor: it goes to a higher step instead.
- **Theory, not a quiz.** A note card's `front` is the name of the concept, rule or exception it states, never a question, and its `answer` is the theory itself. The prompt's own examples ("광합성", "ㄷ 불규칙 (듣다)", "opportunity cost") are not the owner's, which name concepts on the eval's grammar page.
- **Topic.** Every card carries `topic`, the name of the page section it comes from: the heading it sits under without its numbering, or the page's title where it has no headings. It is 1 to 60 characters, in the schema, the parser and the prompt, and cards of one section share it. The function keeps every other field, `step` and `short` among them, so an app that has not updated reads a card as before.
- **Steps and invention.** Every step keeps its meaning from ADR 0051, and step 5 offers every card. The rules against inventing a fact, a meaning, a part of speech or an example stand unchanged. The prompt's own examples are not taken from any eval page.
- **Cap.** At most 100 cards. On a page with more, the model keeps every card of steps 1 to 4 and leaves out the last cards of step 5.
- **Coverage.** A notes page's facts are its rules and exceptions. Each fact holds the worked examples the page prints for it, and no worked example is a fact, on any notes page. A card covers a fact when its front and answer hold every one of the fact's terms, as in ADR 0051, in coverage and in the unsupported rate. A card's examples do not count: another rule's worked example can hold a rule's terms, as a "러 불규칙" card's example "이르+어 -> 이르러" holds "르" and would cover the "르 불규칙" rule. A card made of a worked example covers no rule, so it counts as unsupported.
- **Dense page.** The eval's notes ground truth gains `ko-grammar` in `tools/eval/notes.json`: a Korean grammar page in the style of the owner's, written for the project.
  - It holds 30 lines in five sections, with 21 facts across steps 1 to 4: each rule, each vowel group, each contraction rule, and each exception marked with a drawn star or circle. Its worked examples are the examples of their rule's fact.
  - The logic and economics pages' worked examples, one on each of two rules per page, move into their rule's fact the same way, leaving 10 facts on each. No notes page has a step-5 fact; coverage at step 5 still counts every fact.
  - `tools/eval/generate.py` draws it at four-fifths of the usual size, with the marks in red, in print and handwriting under both distortions. That is samples 33 to 36, and samples 01 to 32 stay byte-identical.
- **Per-page report.** The report gains a section, "Coverage at step 5 per notes page", giving each notes page's coverage at step 5 for every configuration, beside the completion tokens its calls used against `max_tokens`.
- **Limit proposal.** Keep the 100-card cap and `max_tokens` of 16384 until the comparison run reports dense-page completion tokens. If any dense page uses more than 12,000 completion tokens in a call, or fails as invalid output twice, the next change raises `max_tokens` to 32768.
- **Before merge.** The comparison ran on 2026-10-18 over the 12 notes pages with v4 before this revision, at `47569b2d226d124fc3ea23f52f027c9b134c1d96` (`docs/eval/extract-cards.md`, #185). The model set it led to is `CARD_MODEL` on Claude Haiku 5.5 with `CARD_RETRY_MODEL` on Claude Sonnet 5.5, and this ADR changes neither. The revised v4 has not been measured; the merge deploys it.
- **Supersessions.** This replaces ADR 0051's prompt v3, its note card's question-shaped front, and its worked-example facts on the notes pages.

## Consequences

- A dense notes page gives a card for every rule and exception at step 5, and no card for a worked example, so a page of many worked examples gives fewer cards than v4 before this revision did. The lower steps stay subsets of step 5, each holding what its step describes.
- A note card reads as a statement of the theory under the concept's name, and every card names its section, which ADR 0057's Review groups by.
- Each card's reply grows by its `topic`, a few completion tokens.
- Replies on notes pages grow longer, so a call costs more completion tokens and takes longer.
- The eval can now show whether a model covers a dense page at step 5, page by page, and whether its reply approaches the output cap.
- The 2026-10-18 report's coverage was counted against the earlier truth, with worked examples as facts and examples counted, so its numbers do not compare with a run under this truth.
- Merging deploys v4 to every user at once. An unmeasured regression reaches users unless the comparison runs first.

## Signs the decision was wrong

- Step-5 coverage on the dense page stays well below the earlier pages for every configuration, so a prompt alone cannot make one call exhaustive.
- The unsupported rate or invented examples rise under v4, as the push to cover everything turns into filler, worked-example cards, or examples the page does not print.
- Note fronts come back as questions, or answers restate the front without the theory.
- Topics come out too fine or too coarse for ADR 0057's switches, such as one card a topic, or one topic for a page with several headings.
- Users find the lower steps crowded with details after v4, so "a higher step instead" does not hold.
- A dense page's reply is cut off at `max_tokens`, as invalid output twice or completion tokens near 16384.
