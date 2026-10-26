# ADR 0110: Blank a span of a table cell's text, stored at table block v2 beside whole-cell blanks

> Status: accepted
> Date: 2026-10-27

Append-only: once merged, the body below is not rewritten. A fact later found wrong is corrected in an appended note, not edited out; a revised decision is a new ADR that supersedes this one.

## Context

- **Issue #413** records the owner's request of 2026-10-27, from the example on #412: comparison tables hold sentences in their cells. In a history table the cell for 부여 × 정치 reads "5부족 연맹체, 왕 아래 마가·우가·저가·구가…", and the learner wants only "5부족 연맹체" hidden, the rest of the cell as the cue.
- **[ADR 0068](0068-store-a-table-or-cloze-card-as-typed-content-blocks-and-draw-it-whole-its-blanks-filled-in-place-once-answered.md)** stores a table block's blanks as whole cells, each a `{row, column}`.
- **[ADR 0092](0092-make-each-chosen-cloze-word-a-blank-of-its-own-without-its-punctuation-narrowable-to-letters-and-keep-stored-blanks-through-an-edit.md)** and **[ADR 0101](0101-edit-a-cloze-as-one-face-with-its-blanks-as-blocks-in-the-line-and-a-single-insert-blank-action.md)** make a cloze blank a span of its line's characters, made from a text selection, drawn as a block in the line, and kept through an edit that leaves it whole.
- **[ADR 0102](0102-edit-a-table-in-its-cells-with-a-toolbar-over-it-and-no-mode-switch.md)** edits a table in its cells, with "빈칸" a toggle on the selected cell.
- **[ADR 0106](0106-store-each-card-s-template-and-each-block-s-version-and-id-derive-one-face-or-front-back-from-blanks-and-keep-unknown-shapes-unchanged.md)** gives each block a version, upgraded on read by one upcaster step per version, and keeps a block above a build's version unchanged, shown as needing an update.
- **The issue's constraints:** the span form is stored at table block `v: 2`, with an upcaster from v1 that keeps whole-cell blanks whole; a v1 reader keeps a v2 table unchanged; photo import's tables keep whole-cell blanks until #412's research decides how import chooses blanks; no migration.
- Alternatives considered:
  - **A span as an optional `start` and `end` on a `blanks` entry.** A v1 reader matches `{row, column}` and ignores the rest, so it would read a span as its whole cell, were the version bump ever missed. It also lets an entry hold a `start` with no `end`.
  - **A cell holding `___` with its answers, as a cloze's text does.** Every reader of the cells, the card key, the back's filled text and the duplicate rule, would have to fill the cell first, and a cell could no longer hold `___` as text.
  - **A cell as a list of text and blank runs.** A cell would stop being a string, so every reader of `rows` would change, for the same information the spans hold.
  - **Turning a whole-cell blank into a span over the whole cell on upcast.** The issue keeps whole-cell blanks whole, and a whole cell stays whole however its text is later edited.
  - **A separate remove control for a span.** The cloze form removes a blank through its one action (ADR 0101); the table's one action is "빈칸".

## Decision

- **The payload at v2:** `{columns, rows, blanks, spans}`.
  - `columns`, `rows` and `blanks` are as v1 has them: `blanks` are whole cells.
  - `spans` is a list of `{row, column, start, end}`: a run of a body cell's text, from `start` to `end` in the cell's UTF-16 code units, as both clients index a string.
  - A span holds more than whitespace, lies inside its cell, overlaps no other span, and is never in a cell that is a whole blank. One cell may hold several spans.
  - The table holds at least one blank, whole or span. A table that breaks any of this is unreadable, as a broken v1 table is.
- **The upcaster.** One step turns a v1 payload into v2's by adding an empty `spans`; its blanks stay whole cells. A write writes v2. A v1 build keeps a v2 table as `UnsupportedContent`, unchanged, and shows that it needs an update (ADR 0106).
- **Text.** A cell's text is stored whole, so the card key, the back and search read every cell as before.
- **The editor** (refines ADR 0102's "빈칸"):
  - A body cell's spans are drawn as blocks in its text, on `brandTint`, as the cloze line draws its blanks. A whole blank stays a cell tinted `brandTint`.
  - With text selected in the selected cell, "빈칸" makes that run a span, replacing the spans it overlaps; a cell that was a whole blank becomes a cell of spans. A selection of whitespace alone makes none. With the selection inside a span, "빈칸" shows on and turns that span back into text.
  - With no text selected, "빈칸" toggles the whole cell as before; making a cell whole drops its spans.
  - An edit to a cell keeps every span it leaves whole, before or after the changed part, as a cloze line keeps its blanks. On save each span moves with its cell's trim.
  - A cell holding spans is read with ", 빈칸" after its place, as a whole blank is.
- **Drawing.** Study, the deck list and the whole-card views, on the phone and the web, draw a span inside its cell's text, empty as an empty blank is and filled in place once answered, the rest of the cell drawn as it is. A screen reader reads each empty span as "빈칸" inside its cell's text.
- **Photo import** writes whole-cell blanks only, now at v2 with no span, until #412 decides how import chooses blanks.
- **No migration.** No stored row is rewritten; a v1 table becomes v2 on its card's next write.
- This **extends** ADR 0068's table block and **refines** ADR 0102's "빈칸" toggle.

## Consequences

- A table cell can hold a sentence with a key phrase to recall, the rest of the cell the cue.
- A table a v2 build writes is shown as needing an update on any build before it, and kept unchanged there.
- A span's offsets index the cell's text, so a writer that changes a cell outside the editor must move or drop its spans.
- Making a span needs a text selection inside a cell, a long-press and its handles on a phone.

## Signs the decision was wrong

- Users ask for a span to reach across cells, which the per-cell offsets cannot hold.
- A span is found moved off its words after an edit, which would mean offsets are the wrong anchor for cell text.
- Users tap "빈칸" with a caret inside a span expecting to remove it, and lose the cell's spans to a whole blank instead.
