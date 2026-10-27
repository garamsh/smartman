# ADR 0114: Write every card as a 자유 block list, remove the 앞뒤, 빈칸 and 표 forms, and migrate every card to `free`

> Status: accepted
> Date: 2026-10-27

Append-only: once merged, the body below is not rewritten. A fact later found wrong is corrected in an appended note, not edited out; a revised decision is a new ADR that supersedes this one.

## Context

- **Issue #438** records the owner's decision of 2026-10-27: "카드 생성 페이지 ui도 변경해야할듯. 일단 기존 다른 카드 형식들 없애고 자유방식만 쓰자 … 기존 데이터들도 새로운 구조에 맞게 잘 마이그레이션 하고." The owner approved migrating the stored data the same day.
- **[ADR 0083](0083-write-every-card-kind-by-hand-in-a-form-of-its-own-chosen-by-a-kind-switch-each-deck-remembers.md)** and **[ADR 0100](0100-merge-the-word-kind-into-basic-type-each-sense-s-label-and-offer-the-user-s-labels-above-the-keyboard.md)** give each kind a form of its own, chosen by a switch each deck remembers on the device under `deckCardKinds`.
- **[ADR 0106](0106-store-each-card-s-template-and-each-block-s-version-and-id-derive-one-face-or-front-back-from-blanks-and-keep-unknown-shapes-unchanged.md)** makes each side a list of typed, versioned blocks. The template only seeds the editor, and study draws by `oneFaceOf`, never by the template.
- **[ADR 0108](0108-add-a-free-template-and-an-add-control-that-puts-any-block-on-either-side-of-every-template.md)** adds 자유 (`free`, version 1), a pure block list, and lists the blocks added to the other templates after their forms.
- What the forms do that the block list did not, checked against `card_editor_screen.dart` before this change:
  - The 앞뒤 form's back turns from text into senses once a label or a second meaning is typed.
  - It gives each text block beside a back's senses a field of its own, "덧붙인 내용".
  - It edits a front that holds senses as text.
  - The 빈칸 and 표 forms write the back themselves, as the line filled or as the table's name and the table filled.
  - The 빈칸 form shows its action bar whether or not the line has focus.
  - The 표 form labels its front field "앞면 · 표 이름" and refuses an empty name.
  - The 앞뒤 form puts the focus in the front when a new card opens.
  - Every other capability already lives in the blocks: the label presets above the keyboard and typed labels (뜻 목록), cloze span editing and its one action (빈칸 문장), and the table's cells, toolbar and spans (표).
- Alternatives considered:
  - **Keep the forms, and make 자유 the default.** The owner asked for the forms to go.
  - **Leave the stored templates as they are, and open every template in the block editor.** The rows would keep naming a form that no longer exists. The owner asked for the data to be migrated.
  - **Rewrite the content to a canonical 자유 shape,** for example a cloze card's derived back dropped. ADR 0106 keeps content and its encoding, and the issue's constraints forbid it. A card's blocks already are a 자유 card's blocks.
  - **Keep each migrated card's template in a backup table, with a revert,** as the senses and plan-versions migrations keep what they change. Those changed content or terms that nothing else records. This migration changes only `template`, which seeds nothing once the editor has one mode, and leaves content untouched, so a value kept would restore nothing a reader uses. A backup table would also need rows in `supabase/preview-seed.sql`, outside this change. The PM decided against the backup on issue #438, 2026-10-27.
  - **Search a card's stored back whatever its face,** as the deck screen did. A former 빈칸 or 표 card keeps the back its form derived, and that back no longer follows its front once the front is edited. Study never shows it, so a match on it finds a card by text the user cannot see.
  - **Bump each migrated card's `updated_at`,** so the server's copy wins every merge. A device's edit not yet pushed would then lose to the migration.
  - **Make a new card's back a 뜻 목록, so a label can be typed at once.** A plain back would then be stored as senses. ADR 0100 refused that, because the web, photo import and a merged back read text there.

## Decision

- **One editor.** A new card opens as 자유, with one empty 글 on each side and the focus in the front's. An existing card opens with all its blocks, in order, whatever its template. The kind switch, `CardKind`, the forms and the remembered kind are removed.
  - The add sheet offers every block type: 글, 뜻 목록, 표, 빈칸 문장, 사진 and 음성.
  - The one meaning of a 뜻 목록 carries the label field, the presets above the keyboard and "뜻 추가". A label typed on a back is therefore typed in a 뜻 목록, which saves as senses. A 글 saves as text.
  - A text block beside a back's senses is a 글 block of its own. A front that holds senses opens as a 뜻 목록.
  - A back is the blocks listed on it. Nothing writes a cloze's or a table's back for it. A new one has no back block, since a blank makes it a card of one face. A stored back stays a 글 block and is not rewritten when the front is edited.
  - A 빈칸 문장's action shows while its line has focus. A table's name is a 글 before the 표, and a 표 needs no name.
  - A 글 left empty is not saved and keeps no side from saving, so a new cloze or table card saves with its back's untouched 글. A side is then required by its own rule alone: the front always, the back unless the card is studied on one face. While a required side holds nothing to save, its empty 글 asks for text.
- **What the forms did that the block editor drops,** accepted by the PM on issue #438, 2026-10-27, each for its reason:
  - A back no longer turns from text into senses once a label is typed; the 글 is swapped for a 뜻 목록, two taps more. A back that changes its own type as it is typed is the form-specific behaviour the owner asked to remove, and a plain back stays text, as ADR 0100 requires.
  - The 빈칸 action bar shows only while its line has focus. The form held one line, so its bar always had a line to act on; a side may now hold several 빈칸 문장 blocks, and the focus says which one the action blanks.
  - A table's name is optional. The name was the 표 form's derived back, and a card with a blank is studied on its one face, so nothing reads a name the user did not write.
  - A front that holds senses opens as a 뜻 목록, not as text. It is edited as it is stored, and the note that a typed `[명]` would be saved as text goes with the text field.
  - "덧붙인 내용" fields become 글 blocks. They were 글 blocks in storage already; the editor now shows them as such.
  - The kind each deck remembered goes, since there is one kind to remember.
- **Search.** The deck screen's search reads what study draws: the one face `oneFaceOf` gives a card with a blank, and its front and back otherwise. A former 빈칸 or 표 card's stored back is not searched, and no migration rewrites it.
- **Screen-reader labels.** A card studied on one face is read as that face, with its blanks and then filled, on its deck row, the previous card and the day's last card from an earlier session, as search reads it. Its stored back is not read.
- **File names.** `word_form.dart`, `cloze_form.dart` and `table_form.dart` become `senses_block.dart`, `cloze_block.dart` and `table_block.dart`, with their tests, since no form remains and each holds one block's editor. The PM accepted the renames on issue #438, 2026-10-27.
- **The template.** Every card the app writes, by the editor, photo import, a copy or a merged back, records `free` at version 1.
  - A template an earlier build wrote (`flip`, `cloze`, `table` or `free` at version 1), or no template, opens in the editor (`canEdit`).
  - Any other template, or a later version, opens read-only and is never rewritten, a merged back included, as ADR 0106 has it.
- **The data.** Every live card of `flip`, `cloze` or `table` at version 1, or of no template, becomes `free` at version 1. Its content, card key and `updated_at` are not changed:
  - on the server, by migration `20261027140000_card_template_free.sql`. It keeps no backup: only the template changes, which seeds nothing once the editor has one mode, and the content is untouched;
  - on each device, by schema step 13, which also keeps each card's `dirty` flag.
  - A tombstone, and a template or a version no build of this app wrote, is left alone.
- **Sync.** The server's update draws each card a new revision and keeps its `updated_at`, so every device pulls it.
  - A device holding the card synced takes the server's copy on the tie, which equals its own once its schema step has run.
  - A device with an edit not yet pushed holds a later `updated_at`, or wins the tie as an unsynced row. Its edit, already `free` after its step, is pushed over the server's.
  - A device still on an earlier build opens a pulled `free` card as 자유, which it knows. A card it writes in an old form is pushed with that form's template. This build opens that card in the block editor and records `free` on its next write.
- **Supersedes** ADR 0083's forms, its kind switch and the kind each deck remembers; ADR 0100's kind and its basic form, keeping its typed labels, its label presets and the "품사 표시" screen; and ADR 0108's forms and its split of a card's leading blocks into its form.

## Consequences

- The editor is one block list, so a card is written and read the same way whatever template it came from, and the editor code drops the form-split logic.
- A vocabulary card takes one more step: the back's 글 is swapped for a 뜻 목록 before a label is typed.
- A cloze or table card made now has no back block, and an edited one keeps its old back. Study draws its one face, so neither shows there, and the deck screen's search does not read it.
- The device storage under `deckCardKinds` stays on devices that wrote it, read by nothing.
- The server migration draws a new revision for every live card, so every device pulls every card once.
- The server migration runs in one transaction, and the revision trigger takes a transaction-level advisory lock per user, so it holds one lock for every user with a live card until it commits. A user count large enough to exhaust the lock table would fail the migration and roll it back whole.
- Known limit: `editCard` records `free` without re-reading whether the stored row is still one `canEdit` accepts. A card a later build rewrote, pulled while this build's editor had it open, would be overwritten by the save. The build before this change had the same gap.

## Signs the decision was wrong

- Users add vocabulary cards with the label in the 글's text, such as "[명] 사과", rather than in a 뜻 목록. That would ask for a 글 that becomes senses once a label is typed, as the 앞뒤 form's back did.
- Users ask for a cloze's or a table's back to follow its front. That would ask the editor to derive a back again.
- Cards an earlier build keeps writing in its forms keep reaching the server long after the store release, which would ask for a second migration or a server-side default.
