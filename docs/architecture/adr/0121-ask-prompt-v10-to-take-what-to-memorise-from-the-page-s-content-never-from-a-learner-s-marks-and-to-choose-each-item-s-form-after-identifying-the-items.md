# ADR 0121: Ask prompt v10 to take what to memorise from the page's content, never from a learner's marks, and to choose each item's form after identifying the items

> Status: accepted
> Date: 2026-10-28

Append-only: once merged, the body below is not rewritten. A fact later found wrong is corrected in an appended note, not edited out; a revised decision is a new ADR that supersedes this one.

## Context

- **Issue #474, the owner's direction of 2026-10-28.** The model tries to capture the owner's handwriting as well, and accuracy has dropped because of it. The extraction must understand what the photo teaches, identify what is to be memorised, choose a fitting card form for each item, and make cards a learner can study.
- **Prompt v9, the active version** (`prompt_v9.ts`, migration `20261019230003_activate_prompt_v9.sql`, [ADR 0080](0080-ask-prompt-v9-to-name-the-rule-on-every-card-under-it-and-save-it-as-a-version-an-admin-activates-after-the-pm-s-two-eval-runs.md)):
  - its "Handwriting first" rule makes every tip, trap or note the writer added by hand, and every line the writer marked, a card of its own whose front starts with "★ " ([ADR 0063](0063-ask-prompt-v6-for-atomic-typed-cards-and-a-vocabulary-entry-s-senses-and-eval-long-answers-and-senses.md));
  - its last paragraph keeps "handwritten tips" ahead of other cards on a page over 100 cards.
- **The owner's page (#412).** A printed comparison table of 해커스 한국사 "초기 국가", five states over five aspects, each cell several bullet lines, carrying the learner's underlines, circles and red notes in the margins.
- **#412's measurements** show stage 1 reading marks well on Haiku (mark recall 86, precision 92), and leave open whether a mark should decide what to blank or ask.
- **The eval had no truth for annotations.** On the four pages with the writer's additions in pen, `ko-auxiliary`, `ko-numerals`, `ko-honorifics` and `ko-components` (samples 37 to 44 and 48 to 55), each addition was a fact, so a prompt that leaves them out would score lower coverage by design. No page drew the owner's style.
- Alternatives considered:
  - **Ignoring marks entirely.** A mark is the learner's own signal of importance. Read only to order items at the 100-card cap, it costs nothing on a page under the cap and keeps the learner's choice where items must be left out.
  - **A mark choosing the word a cloze blanks.** #433's run found that a cloze for every line, examples and headings included, raised unsupported cards; that question belongs to stage 2's shapes (#412), not the single call.
  - **Keeping the additions as facts and adding the annotation metric beside them.** v10 would then lose coverage on the 16 pages for doing what #474 asks, and v9's "★ " cards would count as supported, so the comparison would favour the behaviour being removed.
  - **Treating additions on a handwritten page as content.** On the eval's handwriting pages the additions are in another ink, as they are over print. One rule for both keeps the prompt shorter and the truth the same in every hand.

## Decision

- **Prompt v10** (`supabase/functions/extract-cards/prompt_v10.ts`) is prompt v9 with three rules added at the head of its rules, its handwriting rule dropped and its cap's order reworded:
  - **What to memorise comes from the page's content:** its printed text, or, on a page written by hand throughout, its handwritten lines.
  - **A learner's marks are not content:** underlines, circles, highlights, stars, ticks, arrows, and notes, tips or translations written by hand in the margins, between the lines or in another ink.
    - None becomes a card, no field's text is taken from one, and no front starts with "★" or another mark.
    - A marked line of the content is carded like every other line, in the words the page prints.
    - A mark only puts its line ahead of unmarked ones when the page holds more than 100 cards. It never adds or drops an item.
  - **Work in two steps:**
    - first identify every item worth memorising, in the page's order: each definition, rule, list member, case or condition under a rule, exception, vocabulary entry and table cell;
    - then choose each item's form: a concept card for a named term, definition, rule or exception, a cloze for a list line or a sentence recalled in context, a table card for a table whose cells are to be memorised, and a vocabulary card for a vocabulary entry;
    - each item is asked once, by one card or one blank.
  - **Dropped:** "Handwriting first".
  - **The cap's order** keeps definitions, rules, judgment cards and exceptions before table and cloze cards, a marked line ahead of unmarked ones of the same rank, and no longer names handwritten tips.
  - **Kept:** every other line of v9, among them one fact per card, the rule's name on every card under a named rule, examples only from the page, and nothing the page does not show. They measured well on v9 and #474 does not touch them.
  - **The response schema and the contract are v9's**, so neither the app nor the function changes.
- **The eval:**
  - `--prompts v9,v10` runs each prompt file on every configuration in one run, one report row each, on `candidates.json`'s Claude Haiku 5.5, the plans' model;
  - a new notes metric, annotations carded, is the share of the learner's annotations some card's front and answer hold every term of, which v10 asks to be 0;
  - on the four pages with additions in pen, each addition is now an annotation of the truth, `{id, terms}`, and no longer a fact;
  - samples 88 to 91 draw the owner's style of page, `ko-early-states`: a printed comparison table of five states marked in red pen, with three red notes in pen, each an annotation.
- **How v10 reaches users:**
  1. the PM runs `tools/eval/run.ts --prompts v9,v10`;
  2. v10 is activated only if it measures at least as well as v9 (#474). The activation goes through the prompt store ([ADR 0073](0073-keep-the-extraction-prompt-as-append-only-versions-in-the-database-served-by-an-active-and-an-admin-only-test-label-and-record-what-served-each-call.md)): a migration as for v9, or the admin area once #473 is fixed.
  - Merging changes nothing a user is served.

## Measured result

- Not yet measured. The PM's run fills this section before this ADR merges. If the ADR merges first, the result is appended as a dated note.

## Consequences

- A photo of a printed page the learner wrote on yields cards of what the page teaches. The learner's own notes are not imported. A learner who wants one as a card types it in the editor.
- Coverage and unsupported cards on samples 37 to 44 and 48 to 55 are not comparable with reports before #474: their additions left the facts, so v9's "★ " cards now count as unsupported there, and the annotation metric counts them too.
- v10 is 13,237 characters against v9's 11,838, within the store's 20,000, and 1,397 bytes longer, so at most about 1,400 more prompt tokens. At Claude Haiku 5.5's $0.1000 per million prompt tokens that is at most $0.00014 a photo, about 6% of v9's measured $0.0022. The PM's run measures the whole, output included.
- `prompt_v9.ts` and `prompt_v10.ts` hold two near-identical texts. `prompt_v10_test.ts` fails when v10 differs from v9 by anything but its stated lines.
- The two-stage eval reads samples 88 to 91 too, so its run plans more calls.

## Signs the decision was wrong

- On the PM's run, v10's coverage or vocabulary F1 falls below v9's, or its unsupported share rises, on the pages without annotations, where the two prompts' rules about content are alike.
- Annotations carded stays above 0 under v10, or a printed line the learner marked goes uncovered more often than an unmarked one.
- A handwritten page's own lines go uncovered because the model reads them as a learner's notes.
- The owner reports wanting the margin notes as cards after all, which would make the choice the user's per import (#412's principle) rather than the prompt's.
