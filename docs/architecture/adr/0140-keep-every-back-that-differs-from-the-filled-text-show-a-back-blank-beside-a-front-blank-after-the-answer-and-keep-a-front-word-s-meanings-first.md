# ADR 0140: Keep every back that differs from the filled text, show a back blank beside a front blank after the answer, and keep a front word's meanings first

> Status: accepted
> Date: 2026-11-02

Append-only: once merged, the body below is not rewritten. A fact later found wrong is corrected in an appended note, not edited out; a revised decision is a new ADR that supersedes this one.

## Context

- [ADR 0137](0137-frame-a-card-by-its-blocks-each-block-type-deciding-whether-it-has-a-front-and-a-back.md) is accepted and frozen. Its dry run on production (#488, 2026-11-02) counted 4,038 live cards, 1 `derived_source` back, 6 `derived_filled_text` backs and 0 `o2_back_blank` cards.
- ADR 0137 drops a back of one `text` block on a blanked front when the card's `source` is `import` or `copy`, even where the text differs from the filled text. That text may hold the user's edit, and the owner's goal for #542 is a lossless migration.
- ADR 0137's rule moves a back `cloze`, `table` or boxed `image` as a question. Beside a front blank that puts a back study never drew at the prompt, where O2 says a back shows after the answer.
- ADR 0137 upgrades a v1 `senses` read in a 칸 list to `ask` `term` with an empty `term`. Such a block sat on a front, so it would show nothing before the reveal, against the same ADR's "read as it was drawn".
- Alternatives considered:
  - **Leave a back blank beside a front blank unconverted.** It would keep two shapes in the frame for a case counted at 0.
  - **Add a side to 빈칸 문장 and 표.** It would undo the frame for a case counted at 0.

## Decision

- **Lossless.** A back of one `text` block on a card whose front holds a blank drops only when it exactly equals the front's filled text, for a front of `text`, `cloze` and `table` blocks, and the migration's backup table keeps the original. Any other back is kept, whatever the card's `source`: a back that differs becomes a 글's back. This replaces ADR 0137's `source` test.
- **A back blank beside a front blank follows O2** and shows after the answer. A `cloze` or `table` there becomes a 글 with a back alone of its filled text. A boxed `image` there is placed on the back without its boxes, with its box answers, one per line, in such a 글 when it has any. The backup table keeps the original. A back block becomes a question only on a card with no front blank.
- **A front word's meanings stay first.** A `senses` block moved from a front, or read at v1 in a 칸 list, is a 단어 of `ask` `meaning`. A back `senses` that joins no word is a 단어 of an empty `term` and `ask` `term`, so its meanings show after the reveal.
- ADR 0137 stands on every other point.

## Consequences

- The 1 `derived_source` card keeps its back, and shows it after the answer.
- `supabase/card-frame-dry-run.sql` counts the same cases, and its comment on `derived_source` changes with the migration (#549).
- A filled-text 글 from a back blank no longer holds its blanks, and a boxed photo there no longer its boxes, except in the backup table.
- `supabase/fixtures/card-frame/` states these rules as cases, which the app, the web and the migration each test.

## Signs the decision was wrong

- A re-run dry run finds cards in `o2_back_blank`, whose users want those blanks asked.
