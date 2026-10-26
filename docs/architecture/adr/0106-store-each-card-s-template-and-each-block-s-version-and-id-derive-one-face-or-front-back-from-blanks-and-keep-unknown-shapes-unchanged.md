# ADR 0106: Store each card's template and each block's version and id, derive one face or front then back from blanks, and keep unknown shapes unchanged

> Status: accepted; its one face for a card whose back alone holds a blank refined by [ADR 0108](0108-add-a-free-template-and-an-add-control-that-puts-any-block-on-either-side-of-every-template.md)
> Date: 2026-10-26

Append-only: once merged, the body below is not rewritten. A fact later found wrong is corrected in an appended note, not edited out; a revised decision is a new ADR that supersedes this one.

## Context

- **[ADR 0068](0068-store-a-table-or-cloze-card-as-typed-content-blocks-and-draw-it-whole-its-blanks-filled-in-place-once-answered.md)** stores a card side as a JSON array of blocks, each `{type, payload}`.
  - An unknown `type` is read as `UnsupportedContent` and written back unchanged.
  - A block has no version, so a change to a known type's payload could only be read by guessing.
- **[ADR 0083](0083-write-every-card-kind-by-hand-in-a-form-of-its-own-chosen-by-a-kind-switch-each-deck-remembers.md)** derives a card's kind from its blocks (`card_kind.dart`), and stores none. [ADR 0100](0100-merge-the-word-kind-into-basic-type-each-sense-s-label-and-offer-the-user-s-labels-above-the-keyboard.md) merged 단어 into the kind shown as "앞뒤".
- **Issue #388** records the owner's decisions of 2026-10-26 and the PM's decision from the research reported to the owner:
  - A card records the template it was made from, and each block its version.
  - The merged kind is the template `flip`, shown as "앞뒤".
  - Cards are flexible: each side is a free list of blocks of any type, and a template only seeds the editor.
  - Whether a card is studied on one face or front then back is derived from its content, never stored.
  - Each block's kind and version are named, and each block gains an optional id (the PM's answer to the owner on #388, 2026-10-26).
  - No existing row is rewritten.
- **The PM's correction on #388:** the extraction function returns card fields, not blocks. So the app writes `v` on every block it encodes, photo import's included, and the function is unchanged.
- Alternatives considered:
  - **Store the card's kind, or its study mode.** A stored mode could disagree with the blocks, and the owner chose to derive it.
  - **Rename `type` to `kind`.** Every row on the device and the server holds `type`. A rename would rewrite every card, or have readers read two names forever, for no gain.
  - **A backfill migration of `template` and `v`.** It would rewrite every row and push them all through sync. A row fills in on its next write instead; a one-off backfill, if ever wanted, is a separate change.

## Decision

- **A block's kind and version.**
  - Its kind is its stored `type`: `text`, `cloze`, `table`, `senses`, and later `image` and `audio`.
  - Its version is a new integer `v`, from 1. A block with no `v` is read as v1.
  - A reader upgrades an older `v` to the current shape when it reads it, through an upcaster chain: one step per version for each type (`blockUpcasters`, and the web's of the same name). A write always writes the current `v`. Every type is at v1 today, so each chain has no step yet.
  - A view chooses its renderer by `type` and reads the payload as of `v`.
- **What a reader cannot read.** A `v` above what a build knows is treated as an unknown type is. The block is kept and written back byte for byte (`UnsupportedContent.stored`), and shown as needing an update. A `v` that is not a positive integer, or an `id` that is not text, makes the side unreadable, as a broken payload does.
- **A block's id.** Each block gains an optional `id`, a UUID v7 from the repository's id generator.
  - An edit keeps a block's id: a rewritten block takes the id of the next block of its kind on that side.
  - A block gets an id on its first write, an existing block on its next.
  - Ids are not compared: two blocks of equal kind and content are equal.
  - A later block can name another, as #389's image boxes will, and an edit can match blocks without relying on their order.
- **A card's template.**
  - A card gains `template`, a text naming the template it was made from: `flip` for 앞뒤, `cloze` and `table`; `free` is reserved for the 자유 template's issue. It also gains `template_version`, from 1.
  - The template decides only how the editor opens the card: its form and starting blocks. The editor writes the template of the kind the card is written in.
  - A card with no `template` is read by the derivation of ADR 0083, and records its template on its next write.
  - A card whose `template`, or `template_version`, a build does not know opens read-only in that build's editor. It says the app needs an update, and can still be deleted.
  - Such a card's template is never rewritten: a merged back from photo import keeps it, and its unknown blocks.
- **Study mode from content.** One function, `oneFaceOf(front, back)`, decides:
  - a card with a blank anywhere, a cloze or a table today and later an image box (#389), is studied on one face, the side that holds the blank, the front first, its answers filled in place;
  - every other card is studied front then back.
  - The study views choose their drawing by this rule, never by `template`.
- **Storage.** The server's `cards` gains two nullable columns: `template`, text with no check so a newer app's values sync, and `template_version`, a smallint of at least 1. The device's `cards` gains the same in schema v11. No existing row is rewritten, and sync carries both columns.
- **Media.** A later image or audio block holds a media id from #383, never a URL.
- **Supersedes** ADR 0083's derivation of a card's kind as its only record: the kind is the stored template, and is derived only for a card that records none. This **extends** ADR 0068's encoding with `v` and `id` on each block.

## Consequences

- A block's shape can change between versions without a guess, and a card written by a newer build passes through an older one unchanged.
- Every card write grows each block by `v` and `id`; a card's bytes change on its first write after this build, as its `updated_at` does.
- A card without a template looks the same to every build until its next write fills one in, so the column is not a complete record of the deck until then.
- New kinds, an image with blanks and audio, are added as block types and templates on this foundation.

## Signs the decision was wrong

- A view needs to know a card's template to draw it, which would mean the mode or the drawing depends on more than the blocks.
- Upcasters pile up for a type with many versions, which would ask for a one-off rewrite of the stored rows.
- Cards are often stuck read-only on devices that do not update, which would ask for a lighter way to edit around unknown blocks.
