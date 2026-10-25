# ADR 0083: Write every card kind by hand, in a form of its own, chosen by a kind switch each deck remembers

> Status: accepted; its cloze blank units (adjacent chosen words make one blank; an edited stored cloze's blanks cover whole words) superseded by ADR-0092
> Date: 2026-10-20

Append-only: once merged, the body below is not rewritten. A fact later found wrong is corrected in an appended note, not edited out; a revised decision is a new ADR that supersedes this one.

## Context

- **Issue #270**, the owner on 2026-10-19: photo import makes table, cloze and senses cards, but the card editor writes only a text front and back. The owner asked for the screen to be built directly, without a mock-up.
- **The PM's decisions on #270:**
  - four kinds: basic, word (senses), cloze and table, each in a form of its own;
  - "카드 추가" opens the editor with a kind switch at the top, remembered per deck, and an existing card opens in its own kind, with no switch;
  - the preview draws the card as study will;
  - inline validation in the app's voice;
  - duplicate detection as today;
  - semantics for blanks and table cells, minimum touch targets, and a screen-reader action on each table cell.
- **[ADR 0068](0068-store-a-table-or-cloze-card-as-typed-content-blocks-and-draw-it-whole-its-blanks-filled-in-place-once-answered.md)** opens a table or cloze card read-only in the editor, and a typed card is a text card.
- **[ADR 0075](0075-store-a-vocabulary-card-s-senses-as-a-typed-block-and-show-each-label-in-brackets-before-its-meaning.md)** keeps a senses side only while its text is left as it was; an edited one becomes text.
- **The ui-ux-pro-max guidance** consulted for the forms (its `ux` and `flutter` searches and its pre-delivery checklist):
  - an inline error under each invalid field;
  - a button alternative to any drag;
  - collections that wrap;
  - wide tables that scroll sideways;
  - one primary gesture per region;
  - 44 pt targets;
  - contrast in both themes.
- Alternatives considered:
  - **One free-text form with markup**, such as `[명]` or `{{blank}}` typed into the text. Every reader would parse text, and a typo would silently save a broken card.
  - **Converting between kinds on an existing card.** The PM's decision rules it out: a card's blocks do not map from one kind to another without loss.
  - **Drag to reorder senses.** Dragging would need a button alternative anyway. Up and down buttons serve touch and a screen reader alike, and avoid a drag inside a scrolling form.

## Decision

- **Kinds.** `CardKind` (`app/lib/deck/src/card_kind.dart`):
  - a card is a cloze or a table when its front holds that block;
  - it is a word when its back holds senses;
  - otherwise it is basic.
- **The switch.** A new card's editor shows a segmented switch at the top, "카드 종류". It starts in the kind the deck's last new card was added in, which is kept on the device under `deckCardKinds` (`deckStorageProvider`, overridden at the composition site); a write the device refuses is reported as a storage failure. An existing card shows no switch.
- **The forms** share the front field, the preview, validation on save, the duplicate rule and the bottom actions:
  - **Basic:** a text front and a text back, as before.
  - **Word:**
    - the headword as the front;
    - one card per sense, each with:
      - its labels as chips, each with a remove button;
      - "표시 추가", a sheet of the fourteen parts of speech, `[명] 명사` and so on, and a field for another label;
      - the meaning;
      - the examples, one per line.
    - Senses move up and down and are deleted by buttons named for a screen reader. A word keeps at least one sense.
    - It saves the headword as text and its back as one senses block, followed by any other block the card's back already held, such as its extras.
  - **Cloze:**
    - the line typed once;
    - under it, its words as toggle buttons, each read with its state; adjacent chosen words make one blank;
    - at least one blank is required.
    - It saves a cloze block, `___` per blank with its answer, and the line filled as its back.
  - **Table:**
    - the table's name as the front;
    - a grid that scrolls sideways, with rows and columns added and removed by buttons, its header row editable;
    - a switch between typing the cells and choosing the blanks, so that one gesture serves each region. In the second, a tap toggles a cell as a blank, and each cell carries the screen-reader action "빈칸으로" or "빈칸 해제".
    - A blank must hold text, and at least one is required.
    - It saves the name, a table block and the table filled as its back.
- **Validation** is inline, under the field, on save:
  - an empty front: "내용을 입력하세요";
  - a sense without a meaning: "뜻을 적어 주세요";
  - a cloze with no blank, and a table blank on an empty cell, each in a sentence of the app's voice.
- **Order of delivery.** This is built in three pull requests:
  - first, the switch with the basic and word forms;
  - then the cloze form;
  - then the table form, which removes the read-only editor.
  - Until each lands, a cloze or table card opens read-only, as ADR 0068 had it.
- **Supersessions:**
  - [ADR 0068](0068-store-a-table-or-cloze-card-as-typed-content-blocks-and-draw-it-whole-its-blanks-filled-in-place-once-answered.md)'s read-only editor and "a card the user types is a text card", once the table form lands;
  - [ADR 0075](0075-store-a-vocabulary-card-s-senses-as-a-typed-block-and-show-each-label-in-brackets-before-its-meaning.md)'s "an edited side becomes a text block" for a word's back. A reversed word's front, which holds senses, still edits as text, as its note says.

## Consequences

- Every kind a photo makes can be written and corrected by hand, and a word keeps its structure through an edit.
- Each kind is one more form to keep, each with its own tests and screenshots.
- A card cannot change its kind. To change it, the user deletes the card and adds it again.
- The editor is a scrolling column rather than a lazy list, so every field of a long word is built and its error shows wherever it scrolls.

## Signs the decision was wrong

- Users ask to change a card's kind, or delete cards to re-add them in another kind.
- The label sheet's fourteen parts of speech are too many to scan, or users type the same other label every time.
- Choosing cloze blanks word by word misses the units users want, such as a part of a word.
