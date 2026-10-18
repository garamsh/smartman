# ADR 0063: Ask prompt v6 for atomic, typed cards and a vocabulary entry's senses, and eval long answers and senses

> Status: accepted
> Date: 2026-10-18

Append-only: once merged, the body below is not rewritten. A fact later found wrong is corrected in an appended note, not edited out; a revised decision is a new ADR that supersedes this one.

## Context

- **Notes.** Issue #200 records the owner's decision of 2026-10-18, made from a dense grammar page holding a table, judgment rules and handwritten exam tips.
  - Under prompt v5 ([ADR 0058](0058-stop-asking-the-model-for-a-short-form-and-a-step-with-prompt-v5-and-add-a-notes-sample-with-the-writer-s-additions.md)), one card can hold a whole table, such as "이, 그, 저가 결합된 단어" answering 12 or more forms. Such a card is hard to recall and hard to grade.
  - The owner approved seven rules, the PM's synthesis on #200: atomic cards, tables cell by cell, cloze cards by default, judgment cards, handwriting first, short fronts, and identify cards.
  - The owner's later comment on #200 has the model decide each card's form, concept, cloze or identify, by the page, with identify cards in the topic of their rule. The user no longer chooses a shape.
  - Prompt v5 lets a list taught as one item to recall be one card. [ADR 0055](0055-cover-everything-a-notes-page-teaches-at-step-5-with-prompt-v4-and-eval-a-dense-page-by-coverage-per-page.md) rules that a worked example is never a card of its own; an identify card made from a printed example sentence qualifies that.
- **Vocabulary.** The owner's comment on #200 reports a word-book entry whose card read "[동] [명] [명] 직면하다, 마주하다; 표면, 겉면; 얼굴, 생김새". The model read every sense, but the schema has one `partOfSpeech` and one `answer`.
  - The PM's comment on #200 makes the schema a form the model fills for any layout: `front`, `senses` of `{pos, meaning}` in page order, `extras` of `{label, text}`, and `examples`.
  - #201 adds a card template on the device, which needs a pronunciation the page prints.
- **The coordinator settled, on the worker's questions in the dispatch, 2026-10-18:**
  - a handwritten card is marked by "★ " at the start of its front, with no new field;
  - cloze is the default for a list or table row recalled in context, and a cell card is for a grid whose cells stand alone;
  - a pronunciation goes in its own field verbatim, one per part of speech included, not among the extras;
  - several senses compose, for old apps, an answer of one line per sense with no single part of speech;
  - the eval reads a truth written before senses as one sense.
- **Old apps.** The app's parser on `main` reads the fields it knows and no other (`app/lib/photo_import/src/extraction_client.dart`), so a new key reaches it unread.
- **The eval.** No notes page holds all four structures #200 names, nothing in the report shows an answer listing many items, and no vocabulary page prints several labelled senses for one entry.
- **Cost.** Merging a change to `extract-cards` deploys it (#177), and more cards, or fuller vocabulary cards, mean more completion tokens a call.
- **Alternatives considered:**
  - **A boolean field for a handwritten card.** It needs a schema key that old apps ignore. The "★ " prefix shows in every app, at the cost the coordinator accepted: the card key keeps the star, so a ★ card does not merge with an unstarred card of the same name.
  - **Keeping `answer` and `partOfSpeech` as the model writes them, beside `senses`.** The model would write each meaning twice. The parser composes both from the senses instead.
  - **One string for every part of speech's pronunciation in `extras`.** The template would have to find it among other extras by its label.
  - **Running v5 and v6 side by side in the eval.** As in ADR 0058, it would keep v5's prompt in the code only to measure it.
  - **Copying the owner's pages as samples.** A sample models a page's structure, not its content, as for ADR 0058's page.

## Decision

- **Prompt v6.** `prompt_v6.ts` replaces `prompt_v5.ts`, which nothing imports any more and git keeps. For notes, it asks for the theory and the exceptions in the page's order, one fact per card:
  1. **Atomic.** An answer that would list more than 5 items is split into several cards.
  2. **Tables cell by cell.** A table whose cells stand alone becomes one card per cell or short row, its front the row and column names and its answer the cell. A whole table is never one card.
  3. **Cloze by default.** A list or table row the learner recalls in context gets one card per blank, its front the line with one blank written `___` and its answer what fills it.
  4. **Judgment cards.** A rule that tells A from B gets its own card, its front "A vs B" and its answer the test.
  5. **Handwriting first.** Every tip, trap or note the writer added by hand, and every line marked as important, is its own card, its front starting with "★ ".
  6. **Short fronts.** A front is a short keyword, never a question.
  7. **Identify cards.** Where the page prints example sentences for a rule that sorts words into categories, the model makes an identify card for each, in the topic of its rule: the sentence with the word to judge in single quotes, and the category and the reason. Only from printed sentences.
  - A worked example is never a concept or cloze card; it stays an example on its rule's card.
  - At the 100-card cap, a page keeps its definitions, rules, judgment cards, handwritten tips and marked exceptions before its cloze and cell cards, and those before its identify cards.
  - Every other rule of v5 stands, including the topic and the rules against invention. The prompt's own examples are #200's and are not taken from any eval page.
- **Card type.** Every card carries `type`: `concept`, `cloze` or `identify`, an enum in the schema that the parser requires. Every vocabulary card and every judgment card is `concept`.
- **The vocabulary form.** The model fills, for a vocabulary card:
  - `senses`, 1 to 10 `{pos, meaning}` in page order, `pos` the label verbatim or `null`;
  - `extras`, up to 10 `{label, text}` for anything else the page prints for the entry, under its own label;
  - `pronunciation`, the pronunciation, transcription or reading the page prints, verbatim, or `null`;
  - `examples` as before, and `answer` `null`.
  - A note fills `answer`, with no senses, extras or pronunciation. The parser refuses a card that fills the other kind's fields.
  - Notes still leave out pronunciations.
- **Old fields.** The parser composes them from the senses, so every installed app reads every card. One sense gives `answer` and `meaning` its meaning and `partOfSpeech` its label, as before. Several give one line per sense, its label before its meaning, and no `partOfSpeech`, so `back` reads one sense per line.
- **The eval.**
  - `ko-numerals` in `tools/eval/notes.json`, samples 41 to 44, is a Korean grammar page on 수사 and 수 관형사, written for the project. It has a classification table, judgment rules, handwritten tips with stars, and a side box, which `generate.py` now draws. Its truth is atomic: each table cell is a fact, as are each definition, the judgment rule, the side box, each tip and the trap, 11 facts.
  - `word-book` in `tools/eval/vocabulary.json`, samples 45 to 47, is a word-book page of five headwords written for the project. Each has a pronunciation, one per part of speech on four, two or three labelled senses, and an extra on four.
  - Samples 01 to 44 stay byte-identical.
  - The notes table gains "Long answers": the share of returned cards whose answer lists more than 5 items, counting its parts between commas, middle dots, slashes, semicolons and line breaks.
  - The vocabulary table gains sense precision and recall over entries matched by front, a sense counting when its part of speech and meaning both equal the page's. Part-of-speech precision is per sense. A card matches on its senses' meanings, and a truth written before senses is one sense of its meaning and part of speech.
- **Before merge.** The PM runs v5 against v6 on Claude Sonnet 5.5 over the notes and vocabulary samples, v5 from `main` and v6 from this change. The PM reports coverage, long answers, senses, completion tokens and cost per image. The merge waits for the owner's approval of that cost.
- **The app** decides how it shows identify cards and senses in changes of its own.
- **Supersessions.**
  - This replaces ADR 0058's prompt v5 and its cap order.
  - It replaces the rule of ADR 0055 and v5 that a list taught as one item may be one card.
  - It replaces the single `partOfSpeech` and `answer` the model wrote for a vocabulary card under [ADR 0051](0051-extract-each-card-with-a-question-a-fullest-and-a-short-answer-and-a-detail-step-and-eval-notes-pages-by-terms.md), and the eval's part of speech per card.
  - It qualifies ADR 0055's rule that a worked example is never a card: a printed example sentence may be an identify card.

## Consequences

- A table or a long list becomes many small cards, each recalled and graded on its own, and a judgment between two categories becomes a card of its own.
- A word-book entry's senses keep their labels and order, in every app.
- A page gives more cards, and a vocabulary card more fields, so each call costs more completion tokens and takes longer. How much is unmeasured until the PM's run.
- A handwritten card's front starts with "★ ", in every app, and its card key keeps the star.
- Until the app reads `type`, an installed app shows identify cards with the others on Review, where the user can remove them.
- An installed app shows a card of several senses as one line per sense. It shows no extras or pronunciation until the app reads them.
- `ko-auxiliary`'s truth keeps both judgment methods as one fact, as ADR 0058 decided. Under v6's atomic rule they may come as two cards, which term matching counts as uncovered, so v6's coverage on samples 37 to 40 can fall by design.

## Signs the decision was wrong

- On the PM's run, v6's long answers stay near v5's, so the atomic rule does not reach the model.
- v6's coverage on the notes pages falls well below v5's beyond the `ko-auxiliary` case above, so splitting loses facts rather than adding cards.
- Sense recall on the word-book pages stays low, or labels land on the wrong sense, so the form does not fit how a model reads such a page.
- The cost per call rises more than the owner accepts.
- Identify cards, extras or pronunciations appear that the page does not print, so the form invites invention.
- Users remove most ★ cards, or the star clutters fronts, so a field would have served better.
