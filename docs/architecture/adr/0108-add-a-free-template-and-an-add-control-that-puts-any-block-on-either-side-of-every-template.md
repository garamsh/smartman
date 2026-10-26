# ADR 0108: Add a free template and an add control that puts any block on either side of every template

> Status: accepted
> Date: 2026-10-26

Append-only: once merged, the body below is not rewritten. A fact later found wrong is corrected in an appended note, not edited out; a revised decision is a new ADR that supersedes this one.

## Context

- **[ADR 0106](0106-store-each-card-s-template-and-each-block-s-version-and-id-derive-one-face-or-front-back-from-blanks-and-keep-unknown-shapes-unchanged.md)** made each side a list of blocks of any type. A template only seeds the editor, and `free` was reserved for this decision. The study mode comes from blanks through `oneFaceOf`.
- **[ADR 0083](0083-write-every-card-kind-by-hand-in-a-form-of-its-own-chosen-by-a-kind-switch-each-deck-remembers.md)** and [ADR 0100](0100-merge-the-word-kind-into-basic-type-each-sense-s-label-and-offer-the-user-s-labels-above-the-keyboard.md) give each kind a form of its own. None of them can put a block on a side the form does not seed.
- **Issue #390** records the owner's decision of 2026-10-26. It was approved on the mockup board "유연한 카드":
  - a fourth template, 자유;
  - "+ 앞면에 추가" and "+ 뒷면에 추가" on every template;
  - a menu on each block to move it or delete it;
  - study draws any combination.
- 글, 뜻 목록, 표 and 빈칸 문장 blocks exist. 사진 and 음성 come with #389 and #391.
- Alternatives considered:
  - **Turn every template into block lists.** The 앞뒤, 빈칸 and 표 forms would lose the shape users know. The owner asked for those forms to open as they do now.
  - **Mark which blocks were added, in storage.** That would be a storage change. A block's place already tells, because each form writes its sides in a fixed leading shape.
  - **Reorder blocks by dragging alone.** WCAG 2.2 asks for a way to reorder that needs no drag.

## Decision

- **A fourth template, 자유**, `free` at version 1. The kind switch reads "앞뒤", "빈칸", "표", "자유".
  - 자유 opens with one empty 글 block on each side.
  - Each side is a list of blocks, and nothing else.
- **An add control on every template.**
  - Under each side's blocks, "+ 앞면에 추가" or "+ 뒷면에 추가" opens a sheet of the block types: 글, 뜻 목록, 표 and 빈칸 문장.
  - A type whose block has not landed is not offered.
  - On 앞뒤, 빈칸 and 표, the form opens as before. The blocks added to a side are listed under the form and saved after the blocks the form writes.
- **Each listed block** has a menu: "위로", "아래로" and "지우기". This menu is the way to reorder without dragging.
- **Which blocks a form edits.** An existing card's leading blocks of the shape its template's form writes go to the form, and every block after them is listed.
  - 앞뒤: the front's first text or senses block; the back's first text block, or its first senses block with the text and unreadable blocks right after it.
  - 빈칸 and 표: the front's blocks up to the first cloze or table, and the back's first text block.
  - 자유: none.
  - Nothing is stored to mark an added block.
- **The saved template** is `free` for 자유. Any other template saves its own value, however many blocks are added.
- **Validation.** Every listed block must be complete, as its form requires.
  - A 자유 card needs a block on its front.
  - It needs one on its back unless it holds a blank, which means it is studied on one face.
- **Drawing.** The editor's preview and study draw by `oneFaceOf`, never by the template. A card with a blank is shown on one face, and any other card front then back. Each side's blocks are drawn in order and fitted to their half.
- **The one face of a card whose back alone holds a blank** is its front's blocks followed by its back's. The front stays the prompt, and the back's blanks are filled in place once answered. An empty front adds nothing, so such a card shows its back alone.
  - This refines ADR 0106's "the side that holds the blank" for this case only.
  - A front that holds a blank is still the one face, as ADR 0068's cloze and table cards rely on. A card with no blank is still studied front then back.
  - No form could make such a card before this decision. With 자유 and the add control, a 글 question on the front and a 빈칸 문장 on the back take two taps, and showing the back alone would hide the question (review of #407).

## Consequences

- A card can hold any combination of the four types on either side. 사진 and 음성 join the sheet when their issues land.
- No storage, sync or server change: ADR 0106's encoding already holds any list.
- An existing card's unusual trailing blocks, such as a second text block on a legacy back, now show as their own listed blocks rather than inside the form's field. Saved unchanged, the card is stored as it was.
- A block added to the back of a cloze or table card is stored, but study draws only the face that holds the blank.

## Signs the decision was wrong

- Users add blocks to 앞뒤 cards more often than they pick 자유. That would mean the forms should be block lists too.
- A form absorbs a block the user added, such as a 글 after a back's senses read as "덧붙인 내용". That would ask for a stored mark on added blocks.
- Learners of cards with a blank only on their back expect the front and the back as two faces, not one. That would ask for a front-then-back drawing with the back's blanks filled when the back shows.
