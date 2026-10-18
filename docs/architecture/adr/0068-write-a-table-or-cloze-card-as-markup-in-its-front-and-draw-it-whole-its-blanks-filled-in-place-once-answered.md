# ADR 0068: Write a table or cloze card as markup in its front, and draw it whole, its blanks filled in place once answered

> Status: accepted
> Date: 2026-10-19

Append-only: once merged, the body below is not rewritten. A fact later found wrong is corrected in an appended note, not edited out; a revised decision is a new ADR that supersedes this one.

## Context

- Issue #212 records the owner's request of 2026-10-19:
  - a page's table, and a list or sentence learned in context, become cards that use the whole card face, not the split front and back;
  - a table card shows the whole table with its headers, the cells to memorise as blanks;
  - a cloze card shows a sentence or a list line with its blank or blanks;
  - answering fills every blank in place.
  - One table, or one cloze sentence, is one card for scheduling. Answers stay two buttons, and FSRS is unchanged.
- **The PM's constraints** on the issue:
  - no schema change if avoidable: the card is encoded in today's `front` and `back` text, so the deck, sync, Supabase and the web store it as now;
  - `front` holds the table or sentence with each blank marked, and `back` the same text with the blanks filled, by a small documented markup, such as a pipe table and `{{c::answer}}`, with `back` derived;
  - old app versions show the plain text readably;
  - study (app and web), the deck list, the card editor and photo import's list draw it whole wherever a card is drawn split now, and the import section's direction options do not apply to it;
  - the work comes in two PRs: this one, the format and its rendering, tested with hand-made cards; then the prompt that makes such cards, gated on the owner's cost approval.
- `deck.md` stores a card side as JSON blocks, and a new block type would be read by an old version as `UnsupportedContent`: a labelled placeholder, not readable text. Markup inside a text block needs no schema change, no new block type and no migration.
- Prompt v6's cloze cards ([ADR 0063](0063-ask-prompt-v6-for-atomic-typed-cards-and-a-vocabulary-entry-s-senses-and-eval-long-answers-and-senses.md)) write their blank as `___` with the answer on the back. They hold no blank in this markup, so they stay split until the prompt of #212's second PR writes the markup.
- Alternatives considered:
  - **A `table` or `cloze` content block.** The schema the PM asked to avoid, and an old version shows a placeholder.
  - **A card-level kind field.** A schema change in the app, Supabase and sync.
  - **Markdown tables with a blank as `___`.** `___` cannot say what fills it, so the back could not be derived.

## Decision

- **Markup.** In a card's front text:
  - `{{c::answer}}` is a blank, its answer the text inside, trimmed. An answer holds no brace and no line break.
  - Lines that each start and end with `|`, two or more, are a table, each line a row and its cells split at `|`. A row of `---` cells, colons allowed, under the first rows makes them the header and is not a row. A shorter row is filled out with empty cells.
- **A whole card** is a card whose front holds a blank. Its front is a table when it is one, otherwise a sentence or lines. A card without a blank is split as before, whatever its text.
- **Back.** A whole card's back is its front with every blank filled. It is what an old version, the web's search and a screen reader's answer read; the new screens draw the card from its front alone.
- **Scheduling.** A whole card is one card: one key, from its front's text with its markup, one state and one review per answer, however many blanks it holds.
- **Drawing.** `deck`'s `WholeCardView` draws a whole card's front, and the web's `WholeCard` the same, in spans a button can hold:
  - a sentence in the style of the place it is drawn, centred, and on a study card fitted as a front is; a table in the body size, the full width, its header rows bold on `ground`, inside `outline` lines;
  - an empty blank is its answer drawn so it does not show, on `hairline`, so filling it moves nothing; a filled one is the answer on `brandTint`;
  - it reads as its text with each empty blank as "빈칸", or filled, and a table row by row.
- **Where.** Wherever a card is drawn split, a whole card is drawn whole:
  - **study**: the current card shows it with empty blanks, the previous card and the day's last card fill them, fitted to the card's height, a table scaled down as a whole; the whole-card sheet, titled "카드", shows it filled, without the back;
  - **the deck list**: the row shows it with its blanks empty, filled when the answer is shown, in place of the answer bar; a public deck's split row shows it filled;
  - **the card editor**: the preview and the duplicate sheet show it filled. A question with a blank puts "빈칸을 채운 카드가 답으로 저장돼요" in the answer field's place, and saving writes the derived back. A blank that opens without closing, or holds nothing, is refused on saving with "빈칸 표시가 닫히지 않았거나 비어 있어요" on the question;
  - **photo import's list**: a row whose front holds a blank shows it whole and saves its derived back, and "앞뒤 바꾸기" neither swaps it nor shows where every row of a section is whole;
  - **the web**: the study page's current and previous card, the whole-card dialog without its front and back headings, the session's answer list, which names it filled, and the deck page's grid.
- **Old versions** show the front with its markup as typed, `{{c::파리}}` and the `|` lines, and the back filled: readable, as the PM required.
- This PR changes no function and no prompt. The prompt that makes such cards, and the function's `table` type, are the second PR of #212.

## Consequences

- A table or a line learned in context is one card, studied whole, without a schema change.
- A whole card's back is written from its front on every save of the editor and photo import, so the two do not drift. A back merged into it by an import's "뒷면 합치기" is stored but not drawn.
- A cell or an answer cannot hold `|`, a brace or a line break.
- The editor takes the markup as raw text; there is no table editor.

## Signs the decision was wrong

- Users of an old version find a whole card's front unreadable.
- Users add `{{c::` by hand and get it wrong often enough that the refusal is a common message.
- Tables wider than a phone card become unreadable when scaled down to fit.
