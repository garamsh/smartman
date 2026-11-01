# ADR 0137: Frame a card by its blocks, each block type deciding whether it has a front and a back

> Status: accepted
> Date: 2026-11-02

Append-only: once merged, the body below is not rewritten. A fact later found wrong is corrected in an appended note, not edited out; a revised decision is a new ADR that supersedes this one.

## Context

- **Issue #488** records the owner's direction of 2026-10-28, given in place of the where-blanks-live options of #475: "지금처럼 앞면 뒷면을 틀로 잡지 말고 칸을 틀로 잡을까? 그래서 앞면 뒷면이 필요한 칸도 있을테고 필요없는 칸도 있을테니까. 예를 들어 글의 경우 앞뒤가 필요하고(물론 비워두기 가능) 빈칸 문장은 필요 없고 그렇잖아. 애초에 이걸 입력 형식으로 받는거지." The PM's comment of 2026-11-01 adds that the block types are one input format, shared by the editor, photo import's mapping and the MCP `add_cards` union (#531).
- Today a card is a front list and a back list of blocks ([ADR 0106](0106-store-each-card-s-template-and-each-block-s-version-and-id-derive-one-face-or-front-back-from-blanks-and-keep-unknown-shapes-unchanged.md), [ADR 0114](0114-write-every-card-as-a-free-block-list-remove-the-flip-cloze-and-table-forms-and-migrate-every-card-to-free.md)), and `oneFaceOf` (`app/lib/deck/src/content.dart`) decides from the blanks whether it is studied on one face: the front when the front holds a blank, else the front's blocks then the back's when the back does, else front then back. The editor draws one group per side ([ADR 0117](0117-draw-the-card-editor-as-one-group-per-side-with-a-full-screen-preview-and-every-action-in-words-or-a-row-menu.md)), and its "+ 추가" puts any block on either side ([ADR 0108](0108-add-a-free-template-and-an-add-control-that-puts-any-block-on-either-side-of-every-template.md)).
- What that frame lets a user write that study does not draw as written, from #475's audit at 31f5f70:
  - a back beside a front blank is drawn nowhere, in study or the preview (#481);
  - a 글 on the back beside a back-only blank is drawn at the prompt (#481);
  - the web studies a back-only blank front then back with the answer filled, where the phone studies it on one face (#482, `web/src/features/decks/card-content.ts` `isWholeCard` reads the front alone).
- #475 counted seven placements among live cards, from the code; production row counts were not run:
  1. photo-import and copy cloze cards: front `[cloze]`, back `[text]`, the front's filled text, which photo import writes (`app/lib/photo_import/src/import_list.dart`, `ImportRow.cards`);
  2. the same for table cards: front `[text name, table]`, back `[text]`;
  3. former 빈칸-form cards: front `[cloze]`, back empty or blocks;
  4. 자유 cards with a blank on the front beside other blocks, back anything;
  5. 자유 cards with a blank on the back alone, the one placement with no blank on the front;
  6. a 사진 with boxes on either side;
  7. v6 text cards with a literal `___`, which are not blanks.
  Every card without a blank is outside the seven: a front and a back of 글, 뜻 목록, 사진 without a box and 소리.
- Until the first store release no older app build is kept working ([ADR 0078](0078-keep-no-older-app-or-function-build-working-until-the-first-store-release.md)).
- Alternatives considered:
  - **#475's options (a), (b) and (c)**: blanks on the front only, blanks inside the 글 block, or both. The owner chose none of them.
  - **Keep the two side lists and add a per-block "side" everywhere.** Every block would carry a side, a cloze included, so the side a blank sits on would still be a field with no meaning, which is the frame the owner asked to drop.
  - **Grade each blank block apart, as cards of their own.** The owner asked for one card; ADR 0068 keeps a card with several blanks one card, one key and one state.
  - **Draw every card in place, a 글's back under its front,** with no split card. One rule, but every card without a blank, the most common card, would change its previous card's look, which the issue forbids for a card that already studied well. The owner kept the split (O6).

## Decision

### The frame

- A card is one ordered list of 칸 (blocks). There is no card-level front and back. Each 칸's **type** decides whether it has sides:
  - **sided** 칸 hold a part shown before the reveal and a part added by it: 글, 단어;
  - **placed** 칸 sit on one side, chosen per 칸: 사진 without a box, 소리;
  - **self-revealing** 칸 have no sides: their blanks are the question and filling them is the answer: 빈칸 문장, 표, 사진 with a box.
- "Before the reveal" is the current study card; "after the reveal" is the previous card and its sheet, since the current card shows its question alone and the answer shows once answered ([ADR 0049](0049-study-in-one-flow-that-goes-on-past-today-s-cards-as-recorded-study-with-the-current-card-showing-its-front-alone.md)). The editor's 미리보기 shows the two states before and after a tap.

### Each 칸 type

| 칸 | Stored `type`, `v` | Sides | Fields, the input format | Before the reveal | After the reveal |
|---|---|---|---|---|---|
| 글 | `text`, v2 | front and back, either may be empty, not both | `front`, `back`: text | its front; nothing while empty | its front, then its back |
| 단어 | `senses`, v2 | the word and its meanings, `ask` naming the one shown first | `term`: text; `senses`: 1 or more `{labels, meaning, examples}` as today; `ask`: `term` or `meaning` | the side `ask` names | both |
| 빈칸 문장 | `cloze`, v1, unchanged | none | `text`, each blank `___`; `answers`, one per blank | its line, each blank empty | the line filled |
| 표 | `table`, v2, unchanged | none | `columns`, `rows`, `blanks`, `spans`, at least one blank or span | the table, each blank empty | the table filled |
| 사진 | `image`, v2 | none with a box; a side without one | `media`, `width`, `height`, `boxes` as today; `side`: `front` or `back`, only while it holds no box | with a box: the photo, each box hidden; without: the photo when its side is `front` | the photo, each box revealed with its answer |
| 소리 | `audio`, v2 | a side | `media`, `duration_ms`; `side`: `front` or `back` | its play control when its side is `front`; the first such sound plays once as the card appears, when autoplay is on | its play control |

- **Versions** ([ADR 0106](0106-store-each-card-s-template-and-each-block-s-version-and-id-derive-one-face-or-front-back-from-blanks-and-keep-unknown-shapes-unchanged.md)): a v1 `text` read in a 칸 list upgrades to v2 as a 글 with that text as its front and an empty back; a v1 `senses` to a 단어 with an empty `term` and `ask` `term`; a v1 `image` or `audio` to v2 with `side` `front`. So a block moved from a front into a 칸 list is read as it was drawn, unrewritten, and only a block that moves from a back is rewritten, to say so.
- **Validity**, refused alike by the editor, the web and the MCP function:
  - a 글 with both parts empty is not saved, as an empty 글 is today;
  - a card holds at least one part shown before the reveal and at least one added by it; a self-revealing 칸 counts for both;
  - a 사진 holds `side` exactly while it holds no box;
  - every other rule each type has today stands: a cloze's blanks and answers, a table's blank or span, a box's fractions, a sound's length.
- **One grade.** A card is one card, with one key, one state and one grade, however many 칸 it holds ([ADR 0068](0068-store-a-table-or-cloze-card-as-typed-content-blocks-and-draw-it-whole-its-blanks-filled-in-place-once-answered.md)).

### Study of a card of several 칸

- **A card with no self-revealing 칸** is drawn split, as every such card is today:
  - the current card: every 칸's before part, in order, as the front is drawn now;
  - the previous card: the before parts in the upper half and the parts the reveal adds in the lower, in order, through `SplitCard` ([ADR 0042](0042-show-only-the-previous-and-the-current-study-card-at-one-size-re-decide-the-previous-card-by-a-swipe-and-open-it-on-a-tap.md)); its sheet "앞면" and "뒷면" over the two;
  - the web's previous card and dialog the same, graded by colour alone ([ADR 0105](0105-grade-the-web-s-previous-card-by-its-colour-alone-as-the-phone-does.md)).
- **A card with a self-revealing 칸** is drawn whole, each 칸 in place, in order, through `WholeCardView` and the web's `WholeCard`:
  - the current card: a 글's front as a title, a 단어's asked side, each blank empty as a gap over an underline ([ADR 0119](0119-draw-every-screen-from-one-radius-scale-one-chip-three-type-sizes-a-press-dim-and-three-haptics-and-a-hidden-blank-as-an-empty-underlined-gap.md)), a front photo or sound; a 칸 with nothing before the reveal draws nothing;
  - the previous card and its sheet: every 칸 revealed in place, a blank filled on `brandTint`, a 글's or a 단어's added part under its first part at the back's size and colour (20/600, `ink2`), a back photo or sound in its place; the sheet names no side.
- A card too long for its card steps down and scrolls as [ADR 0123](0123-step-a-long-card-side-down-through-three-sizes-then-scroll-it-inside-a-card-that-keeps-its-size.md) has it; long content is #489's.
- A screen reader reads the 칸 in order, before the reveal each blank as "빈칸", after it filled and each added part after its first.
- The deck screen's row, `CardSplitRow`, the public deck preview and the photo import list draw a card the way its previous card is drawn, in their own styles; the deck screen's and the web's searches and the MCP `search_cards` read every 칸, revealed, since no 칸 is hidden from study.
- `oneFaceOf` and `isWholeCard` go; the one question left is whether a card holds a self-revealing 칸.

### The editor

- The 앞면 and 뒷면 groups go. The card is a column of groups, one per 칸 ([ADR 0117](0117-draw-the-card-editor-as-one-group-per-side-with-a-full-screen-preview-and-every-action-in-words-or-a-row-menu.md)'s group: white, radius 14, rows parted by hairlines, a field outlined in 1.5 px ink while focused). Each group is headed by its type's name, muted, with its ⋯ of "위로", "아래로" and "삭제" at the heading's end.
  - **글:** two rows, the fields "앞면" and "뒷면", each named inline in muted text. A new card opens with one 글, the focus in its 앞면.
  - **단어:** the field "단어", then the meanings as the 뜻 목록's rows are today (label chip, meaning, "+ 뜻 추가", examples, the label strip above the keyboard), then a row "앞면에 보일 것" with two `AppChip.action` chips, "단어" and "뜻".
  - **빈칸 문장** and **표:** as today, with no side.
  - **사진:** as today; while it holds no box, a row "앞면" and "뒷면" as two chips; it goes when the first box is drawn.
  - **소리:** as today, and the same "앞면" and "뒷면" row.
- After the last group, "+ 칸 추가" in `ink2` opens the sheet "칸 추가": 글, 단어, 빈칸 문장, 표, 사진 and 소리, each with one line but 글.
- The line "빈칸 카드는 앞면에서 바로 답을 맞혀요. 뒷면은 비워 둬도 돼요." goes, with the back it spoke of. A card that shows nothing before the reveal reads "앞면에 보일 내용을 하나 이상 넣어 주세요" under the column, and one that adds nothing by it "뒷면이나 빈칸을 하나 이상 넣어 주세요".
- 미리보기 draws the two states as study does; a split card names "앞면" and "뒷면" over them as today, and a whole card names none, its line under it "카드를 탭하면 답이 보여요".

### One input format

- A card is `{"blocks": [칸, …]}`, and a 칸 is `{"type": …}` with its type's fields from the table, for example `{"type": "text", "front": "capital", "back": "수도"}` or `{"type": "cloze", "text": "The capital of France is ___.", "answers": ["Paris"]}`. Storage wraps each 칸 as today's `{type, v, id, payload}`, its fields the payload.
- Every entry point writes this one format, and each fills only what it alone knows:
  - the editor gives each 칸 its id and a 사진's or a 소리's media through `media`;
  - photo import maps the extraction's cards, whose contract is unchanged (`ai-extraction.md` §Contract), to 칸 in the app and the web: a vocabulary entry to a 단어, its pronunciation and extras to a 글 with a back alone; a note to a 글, swapped by "앞면과 뒷면 바꾸기"; a cloze card to its 빈칸 문장 alone; a table card to a 글 of its name and its 표. It writes no filled-text back;
  - the MCP `add_cards` takes `blocks` in the same union, a 사진 given by an https `url` in place of `media`, `width` and `height`, which the function fetches and stores (#531); `list_cards` and `search_cards` return each card's `blocks` in it. The plain `front` and `back`, with labels and examples, stays accepted and becomes one 글, or a 단어 when it has labels or examples.
- The rules of validity are stated once, here and in `deck.md`; the app, the web and the function each test them on shared fixtures.

### Storage

- A card in the frame records the template `free` at version 2. Its 칸 list is stored in `cards.front`, and `cards.back` is `[]` (O1). No column is added, so sync, the revision trigger, the tombstone purge and the media read policy, which reads `front || back` (`supabase/migrations/20261027100000_media_card_read.sql`), are unchanged.
- A build of the frame reads a `free` v1 card, or one of no template or of `flip`, `cloze` or `table` v1, by converting it on read with the migration's rule below, and writes it in the frame on its next save. A template or version it does not know opens read-only, as today.
- The card key is the text shown before the reveal with every blank filled, in 칸 order: a 글's front, a 단어's asked side, a cloze or table filled, a photo's media id and box answers, a front sound's media id, normalized as today. For every card whose front blocks are moved unchanged it equals the stored key.
- A merged back from photo import appends a 글 with a back alone, unless a line already equals it under the key's normalization.

### Migration of every existing card

- **Rule, one function** on the server (`private.card_frame`, SQL, as `private.senses_block` was) and on the device (schema step 14), with shared fixtures:
  - the front's blocks become the first 칸, in order, unrewritten: a `text` a 글's front, a `cloze`, `table` or boxed `image` itself, an unboxed `image` or `audio` placed on the front;
  - the back's blocks follow, in order: a `text` becomes the back of the next front 글 still without one, else a 글 with a back alone; a `senses` joins the front's one `text` as a 단어 with `ask` `term` when the front is that one `text`, else a 단어 of no term; a front `senses` takes a back of one `text` as its term with `ask` `meaning`; an unboxed `image` or `audio` is placed on the back; a `cloze`, `table` or boxed `image` is moved as it is and becomes a question;
  - a **derived back**, one `text` block on a card whose front holds a blank, equal to the front's filled text or on a card whose `source` is `import` or `copy`, is dropped: photo import and a copy wrote it, and study never drew it;
  - a card holding a block of a type or version the function does not know is left as it is and counted; the app converts it on read.

| # | Placement (#475) | Becomes | What study shows |
|---|---|---|---|
| — | no blank: 글, 뜻 목록, unboxed 사진, 소리 on either side | sided 칸 and placed 칸, a front `text` paired with a back `text`, a word with its senses | unchanged: split, the same blocks in each half |
| 1 | import or copy cloze: `[cloze]` / `[text filled]` | `[cloze]`, the back dropped as derived | unchanged on the phone and the web |
| 2 | import or copy table: `[text, table]` / `[text filled]` | `[글 name, table]`, the back dropped as derived | unchanged |
| 3 | former 빈칸 form: `[cloze]` / empty or blocks | `[cloze]`, then the back's blocks unless derived | unchanged while the back is empty or derived; else the back shows after the answer (O2) |
| 4 | front blank beside other blocks, back anything | the front's 칸, then the back's unless derived | unchanged for the front; a back not derived, which study never drew (#481), shows after the answer (O2) |
| 5 | blank on the back alone | the front's 칸, then the back's blank 칸 as questions | the phone unchanged for the blanks; a back 글, which the phone drew at the prompt (#481), shows after the answer (O3); the web now as the phone (#482) |
| 6 | 사진 with boxes, either side | moved unchanged, a question | unchanged on a front; on a back as #5 |
| 7 | v6 text with a literal `___` | a 글 | unchanged |

- **Server**, by one migration the owner approves first, as ADR 0114's was, in one transaction:
  - `private.card_frame_backup` keeps every row it changes: card id, user id, `front`, `back`, `template`, `template_version` and the `front` it wrote;
  - every live card of `free` v1, or of none or of `flip`, `cloze` or `table` v1, takes its 칸 list in `front`, `[]` in `back` and `free` v2; its `card_key` and `updated_at` are kept, and its revision is drawn anew so every device pulls it;
  - a tombstone, and a template or version no build wrote, is left alone.
- **Dry run first**: `supabase/card-frame-dry-run.sql`, one select run read-only on production, counts the live cards by placement 1 to 7 and by no blank, the derived backs the migration drops by reason, the backs O2 and O3 decide, the O2 cards whose back holds a blank, which the rule above moves as a question, and the cards it leaves, with up to five card ids of each and no card content. The owner approves the migration on these counts (`server.md` §Gate). #475's counts were not run, so this report is the first.
- **Device**: schema step 14 applies the same rule to every live card of those templates, keeping each card's `dirty`, `updated_at` and key; a device holding the card synced takes the server's copy on the tie, and an edit not yet pushed, already in the frame after its step, is pushed over it, as ADR 0114's sync has it.
- **Rollback**, `private.revert_card_frame()`, run again until no device writes the frame:
  - a backed-up card whose `front` still equals the one the migration wrote takes back its `front`, `back`, `template` and `template_version` exactly;
  - a card written in the frame since takes the projection of its 칸 list: every before part as its front, every added part as its back, a self-revealing 칸 on its front, and `free` v1;
  - each takes a new revision, so devices pull it. The server is reverted before the previous app build ships, since that build reads a `free` v2 card as read-only and its v2 blocks as needing an update. A frame build reads the reverted cards by its on-read conversion. The backup table is dropped by a later migration once the owner closes the window.

### What this does to the open issues

- **#481** is moot: no back is drawn nowhere, and no back block is drawn at the prompt; every 칸 shows its fields in the editor and its parts in study. Close it with the implementation.
- **#482** is moot: the web reads the frame by the same rule, and no rule reads the front alone. Close it with the implementation, its acceptance a test of the frame's web study.
- **#480** and **#483** are closed. Their fixes stand: the 빈칸 문장 칸 keeps its line editor and its action.
- **#479** is fixed independently and first, since every blank 칸 depends on selecting in its line.

### The owner's choices

The owner decided all six on 2026-11-02 (#488):

- **O1, where the 칸 list is stored:** in the existing `front` column, with `back` `[]` and `free` v2. No column, sync payload or media read policy changes, and the column's name says less than it holds until a later ADR renames it.
- **O2, a back beside a front blank that study never drew** (placements 3 and 4, not derived): it shows after the answer, as the card's added parts.
- **O3, the back text of a card whose only blank is on its back,** which the phone drew at the prompt: it shows after the answer, since it was written as a back and the web drew it so.
- **O4, the vocabulary 칸:** 단어, the word and its meanings in one 칸, the user choosing through `ask` which shows first. One group asks for exactly a vocabulary card's fields, and photo import's "앞면에 뜻" is its `ask`.
- **O5, the word on screens:** 칸, the owner's word: "+ 칸 추가", "칸 추가". A 사진's "빈칸 추가" stays, and the two are told apart by 빈.
- **O6, a card without a blank:** split as today, and drawn in place only when a self-revealing 칸 is present, so no text card's previous card changes.

### Supersedes, once implemented

Each stands until the implementation lands:

- ADR 0106's study mode from blanks (`oneFaceOf`) and its two side lists, keeping its versions, ids and unknown shapes;
- ADR 0108's add control on either side, and its back-only one face;
- ADR 0114's side lists in its one editor, keeping the one editor;
- ADR 0117's one group per side, keeping its groups, preview screen and menus;
- ADR 0068's filled-text back that photo import and a copy write.

## Consequences

- What the editor shows is what study draws: each 칸's fields are its parts, and no placement hides one or moves one to the prompt.
- One union serves the editor, photo import and MCP, so a card an AI writes renders as a hand-made one; the app, the web and the function each keep a validator of it, held together by shared fixtures.
- A vocabulary card is one 단어 group in place of a 글 on the front and a 뜻 목록 on the back.
- Every live card is rewritten once and pulled by every device once; the migration holds the revision trigger's per-user advisory lock for every user until it commits, as ADR 0114's did. The backup table needs rows in `supabase/preview-seed.sql`.
- `cards.front` holds the whole card until a later rename (O1).
- A shape-5 card keeps its stored key, which no longer holds its back blank's text, until its next edit; a new card equal to it is then not found a duplicate.
- `sync.md`, `server.md`, `media.md` and `home.md` take the implementation's changes when it lands.

## Signs the decision was wrong

- Users write 글 with a back alone beside a blank to explain the answer, often enough that a 빈칸 문장 or 표 wants a back of its own.
- Users ask for a 표 with no blank, shown as it is, which would make 표 a placed 칸.
- Users confuse "칸 추가" with a photo's "빈칸 추가", or a cell of a 표.
- The dry run finds many backs it would drop as derived that their users had edited, which would ask for a narrower test.
- Vocabulary users split a 단어 into one card per meaning, asking for a grade per sense.
