# ADR 0092: Make each chosen cloze word a blank of its own, without its punctuation, narrowable to letters, and keep stored blanks through an edit

> Status: accepted
> Date: 2026-10-21

Append-only: once merged, the body below is not rewritten. A fact later found wrong is corrected in an appended note, not edited out; a revised decision is a new ADR that supersedes this one.

## Context

- **[ADR 0083](0083-write-every-card-kind-by-hand-in-a-form-of-its-own-chosen-by-a-kind-switch-each-deck-remembers.md)** offers a cloze line's words as toggle chips, a word being a run of characters other than whitespace. It also rules that adjacent chosen words make one blank and that, once a stored cloze is edited, every blank covers whole words.
- **Issue #308** (QA, accepted by the PM on 2026-10-20) found three things:
  - **An edit merges a list cloze's blanks.** Prompt v9 makes a list line one cloze with a blank per member, `3인칭 재귀칭: ___, ___, ___, ___` with the answers `자기`, `자신`, `저`, `저희`. Fixing a typo elsewhere in that line turned it into one blank, `자기, 자신, 저, 저희`. Opening the card chose all four words, and they were adjacent, so they joined.
  - **A blank always carried the word's punctuation** (`자기,`).
  - **A Korean word chip is an eojeol with its particle,** so `서울` in `서울은` could not be blanked alone. ADR 0083 named this in its signs: "Choosing cloze blanks word by word misses the units users want, such as a part of a word."
- **The PM's decision on #308:** supersede ADR 0083's cloze blank rules, keeping the storage ([ADR 0068](0068-store-a-table-or-cloze-card-as-typed-content-blocks-and-draw-it-whole-its-blanks-filled-in-place-once-answered.md)) unchanged:
  - each chosen chip is its own blank;
  - a chip's leading and trailing punctuation stays outside its blank;
  - a chosen chip can be narrowed to part of itself through "글자 고르기";
  - a stored card keeps its blank boundaries through an edit that leaves them whole.
- Alternatives considered:
  - **A control to join neighbouring chips into one blank.** Kept out: no case on record needs a blank over two words, and a stored one, such as `on the`, is kept as stored.
  - **Narrowing by selecting text in the line field.** A text selection is hard to make precisely on a phone and is not offered to a screen reader as a choice. Letter tiles are 52-point targets, each read and selectable.
  - **The narrowing control inside the chip**, as a trailing icon. Its target would be well under 44 points.

## Decision

- **Blanks are spans of the line**, not chosen words. A stored cloze opens with each blank where the card has it. A chip shows chosen when a blank falls in its word.
- **A tap on a chip** makes its word a blank of its own, without the punctuation it starts or ends with: the span from its first letter or digit to its last, or the whole word when it holds none. A tap on a chosen chip leaves out every blank in its word. Adjacent blanks stay apart.
- **Under the chips,** each blank is listed in order as "빈칸 n: answer". A blank inside one word has a "글자 고르기" button beside it, which opens a sheet of the word's letters as tiles. A tap on the first letter and then on the last chooses the run between them, and "이 글자로" makes that run the word's one blank.
- **An edit to the line** keeps every blank the edit leaves whole, before or after the changed part, and leaves out a blank it changes. A stored card's blanks, a blank inside a word included, therefore survive a fix elsewhere in the line.
- **Storage is unchanged:** a cloze block's text with `___` per blank and its answers, as ADR 0068 has it.
- **Supersedes** ADR 0083's "adjacent chosen words make one blank" and "once either is edited, every blank covers whole words". The rest of ADR 0083 stands.

## Consequences

- Prompt v9's list and rule clozes survive an edit in the editor, and the form writes the shape photo import writes most.
- A Korean blank can leave its particle outside it.
- A new blank over two words can no longer be made in the form; a stored one is kept.
- The form shows one more list, the blanks with their buttons, under the chips.

## Signs the decision was wrong

- Users ask to blank a phrase of several words, or delete and retype cards to get one.
- "글자 고르기" goes unused while blanks still carry particles, which would mean the control is not found where it is.
- The punctuation rule cuts a blank users meant to keep, for example a hyphenated or apostrophised word, so they narrow or retype it often.
