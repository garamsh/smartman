# ADR 0069: Ask prompt v7 for whole-table and cloze cards as structured fields, exception cards that state what they do, and examples only from the page

> Status: accepted
> Date: 2026-10-19

Append-only: once merged, the body below is not rewritten. A fact later found wrong is corrected in an appended note, not edited out; a revised decision is a new ADR that supersedes this one.

## Context

- **Issue #212**, the owner's request of 2026-10-19:
  - A page's table becomes one card that uses the whole card face. Its headers stay, and the cells to memorise are blanks that answering fills.
  - A list line or sentence learned in context becomes a cloze card with one or more blanks.
  - One table, or one cloze line, is one card for scheduling.
  - The PM split the request in two. Part 1, #212, covers the app's storage and rendering. Part 2 is #217, the prompt.
- **The PM's contract on #217**, decided so that the two parts meet without waiting on each other:
  - `type` gains `table`, and `cloze` stays.
  - A table card carries its column headers, its rows of cells, and which cells are blanks. A cloze card carries its text and its blanks with their answers.
  - `front`, `answer` and `back` stay filled for apps that read only those, as [`ai-extraction.md`](../ai-extraction.md) §Contract asks of every new field.
  - The worker names the fields.
- **[ADR 0063](0063-ask-prompt-v6-for-atomic-typed-cards-and-a-vocabulary-entry-s-senses-and-eval-long-answers-and-senses.md)** has prompt v6 split a table cell by cell, "A whole table is never one card", and give a cloze card one blank. #212 replaces both for cards meant to be memorised as a whole.
- **Issue #188**, closed into #217. The PM's run of 2026-10-18 on the dense grammar page returned exception cards that do not state the exception, such as "'르' 불규칙" answered "'르' 불규칙의 예외".
- **The PM's comment of 2026-10-19 on #217:**
  - Production runs on Claude Haiku 5.5.
  - Over the 47 samples, v6 on Haiku invented 7.0% of its examples, against 1.1 on Claude Sonnet 5.5.
  - v7 is measured on Haiku, and Haiku's invented-examples rate should fall toward Sonnet's.
  - The PM asked that its runs of that day be entered in the ledger.
- **The coordinator's answers on #217's dispatch, 2026-10-19:**
  - The eval's candidates are Claude Haiku 5.5 alone, without a retry, since the owner has decided to drop the Sonnet retry.
  - The ledger takes two entries: the PM's v6 runs, and the key usage left unattributed after them.
- **Apps in use.**
  - The app on `main` refuses a card whose `type` it does not know: `app/lib/photo_import/src/extraction_client.dart` throws `ServiceFailed('a card has an unknown type')`. It ignores keys it does not know.
  - [`server.md`](../server.md) §Edge Function deploys does not merge "a response the apps in use cannot read".
  - The coordinator ruled, on the worker's question, that this change waits for an app that reads `type: table` (#212 part 1). #212 part 1 also makes the parser read an unknown type as a plain card.
- **The PM's first run of v7**, on #225 at `2b3f1a2ea573277b4fd8331e8a94058710d8749c`, Claude Haiku 5.5 over the 55 samples:
  - Table blanks were 95.8, bare exceptions 0.0, the typical notes pages 100 and vocabulary F1 99.5.
  - Cloze blanks were 0.0. On samples 52 to 55, each list line, such as "주성분: 주어, 서술어, 목적어, 보어", came back as a concept card naming the group and answering the list.
  - The dense grammar pages 33 to 36 covered 100, 71.4, 81.0 and 57.1, against v6's 81.0, 71.4, 81.0 and 95.2 on Haiku. Page 36 missed 9 of its 21 facts:
    - four contraction lines came back with fronts such as "ㅗ+ㅏ", without the rule's name the fact's terms hold;
    - one sub-point, a condition under ㅡ 탈락, was dropped;
    - one card paraphrased past its terms;
    - three misread the harsh handwriting, such as "씹다" for "입다".
  - Invented examples were 4.8, against 7.0 for v6. Of the 126 examples returned on the notes pages, 6 were counted invented. One was a printed example shortened, and five were misread characters on harsh or handwritten pages.
- **Alternatives considered:**
  - **Markup in `front` and `answer`**, such as a pipe table with marked blanks. The PM's contract rules it out: every client would parse text, and an old app would show the markup.
  - **The table cell by cell, as in v6, with a new grouping field.** The cells would still be scheduled one by one, against #212's one card per table.
  - **A cloze's text in a field of its own, beside a keyword `front`.** The model would write the line twice, or an old app would lose it. The line already sits in `front`, as in v6.
  - **The blanks of a table as a flag on each cell.** Positions `{row, column}` let the parser refuse a blank outside the table, which #217 asks for, and keep the cells plain text.
  - **Keeping `prompt_v6.ts` beside v7.** Nothing would import it. As in ADR 0063, git keeps the old version.

## Decision

- **Prompt v7.** `prompt_v7.ts` replaces `prompt_v6.ts`. It keeps v6's rules, except as follows:
  1. **Table cards.** A table whose cells are to be memorised, such as a classification grid, becomes one `table` card holding the whole table:
     - its front is the table's name;
     - its headers are kept;
     - the cells to recall are its blanks.
     - A table is never split into a card per cell or per row.
  2. **Cloze cards.**
     - A list line, a group's name followed by its members, becomes one `cloze` card:
       - its front is the whole line with each member written `___`;
       - its answers are the members, in order;
       - it is never a concept card whose answer is the list.
       - A line of more than 5 members becomes several cloze cards of at most 5 blanks, each keeping the group's name.
     - A sentence recalled in context, which has no concept card of its own, also becomes one `cloze` card, with a blank for each word to recall.
     - A cloze never asks what a concept or table card already answers.
  3. **Sub-points.** Every line under a point is covered by a card of its own or by a cloze blank: a member, a case, a condition or a variant of the point's rule. It is never dropped or left only as an example, and its card names the rule it belongs to.
  4. **Exceptions.** Each exception's card states what the exception does, as the page prints it, never only that it is an exception.
  5. **Examples.** An example is copied whole and character for character, and only when the page prints it for that card's entry or rule. No example is shortened, completed, extended, translated or made up. One that cannot be read with confidence is left out. When the model cannot see one printed for the card, `examples` is empty.
  - At the 100-card cap, table and cloze cards come after a page's definitions, rules, judgment cards, handwritten tips and marked exceptions, and before its identify cards.
- **The contract.** The model writes two new keys on every card, `null` where they do not apply, as strict structured outputs require:
  - `table` — `{columns, rows, blanks}`:
    - `columns` is 1 to 8 column headers, the top-left corner included;
    - `rows` is 1 to 20 rows, each exactly as many cells as there are columns, starting with its row header;
    - `blanks` is one or more distinct `{row, column}`, counted from 0 within `rows`, each on a cell that holds text.
    - A header or cell the page leaves empty is `""`. Each is at most 500 characters.
  - `cloze` — `{answers}`: 1 to 10 answers, one for each `___` in the card's front, in order.
  - Only a note's `table` card has a `table`, and only its `cloze` card a `cloze`, and neither card has an `answer` from the model. A vocabulary card is neither.
  - The parser refuses every other combination as invalid output, which is retried once. It also refuses ragged rows, a blank outside the table, on an empty cell or given twice, a table with no blank, and a cloze whose answers do not match its blanks one for one.
- **For apps that read only `front`, `answer` and `back`:**
  - A table card's `answer`, `short` and `back` are the table as plain text: the headers on the first line, then one line per row, cells joined by ` | `.
  - A cloze card's are its answers, one per line.
- **Merge order.** This change merges only once the app that reads `type: table` is the one in use: #212 part 1, which also reads an unknown type as a plain card. Until then, a v7 response holding a table card would fail the whole extraction in the app on `main`.
- **The eval:**
  - `ko-honorifics` is samples 48 to 51. It has a classification table whose six body cells are table blanks.
  - `ko-components` is samples 52 to 55. It has list lines whose seven listed words are cloze blanks.
  - A notes truth may name `tableBlanks` and `clozeBlanks`, each `[{id, terms}]`.
  - Samples 01 to 47 stay byte-identical.
  - The notes table gains three columns:
    - table blanks: the share of a page's table blanks that one blank cell of a table card holds, all terms included;
    - cloze blanks: the same over cloze blanks and a cloze card's answers;
    - bare exceptions: the share of returned cards whose answer names an exception, "예외" or "exception", yet covers no fact.
  - Long answers no longer count a table card, whose answer is its whole table.
  - `candidates.json` holds one configuration, Claude Haiku 5.5 alone.
  - The ledger gains the PM's two v6 runs of 2026-10-19, Sonnet $1.2549 and Haiku $0.0869. It also gains the remainder of OpenRouter's key usage, $5.9865, over the ledger: $0.6806, unattributed.
- **Before merge.**
  - The PM runs v7 on Claude Haiku 5.5 and reports it against v6:
    - coverage, with the dense grammar pages 33 to 36 not falling and the typical notes pages staying at 100.0;
    - unsupported cards and invented examples, neither rising, and Haiku's invented examples falling toward Sonnet's 1.1;
    - bare exceptions on pages 33 to 36;
    - table and cloze blanks;
    - the cost per photo.
  - The merge waits for the owner's approval of that cost, since merging deploys the function.
- **Supersessions.**
  - This replaces ADR 0063's prompt v6, its tables cell by cell, its cloze of one blank, its type of three values and its cap order.
  - It replaces [ADR 0059](0059-keep-one-sonnet-call-per-photo-after-measuring-an-outline-then-fill-pipeline-and-the-newest-models.md)'s eight candidate configurations.

## Consequences

- A page's table reaches the app as one card with its structure, ready for #212's whole-card rendering. A list line reaches it as one card with all its blanks.
- An app that reads only `front`, `answer` and `back` still shows each new card readably: a table as rows of text, and a cloze as its line and its answers.
- Until #212 part 1 is in use, this change cannot merge, since the app on `main` refuses the `table` type.
- Cell-by-cell cards stop for tables to memorise, so a page gives fewer cards, but a table card's reply is larger. How the cost changes is unmeasured until the PM's run.
- The eval scores whether a model uses the new types where the page calls for them, and whether exception cards state their rule. It no longer compares models, until a later change adds candidates back.

## Signs the decision was wrong

- On the PM's run, table blanks or cloze blanks stay low, or tables still come back cell by cell, so the rules do not reach the model.
- Invalid outputs rise on table cards, through ragged rows or blanks outside the table, so the shape is hard for a model to fill.
- Coverage on the notes pages falls, because whole tables cost the facts their cells held.
- Bare exceptions stay on pages 33 to 36, or Haiku's invented examples do not fall, so the rules about exceptions and examples do not reach the model.
- #212 part 1 needs a shape other than `{columns, rows, blanks}` and `{answers}`, so the contract was fixed too early.
- The cost per photo rises more than the owner accepts.
