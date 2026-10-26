# Deck

The `deck` domain: decks, the cards inside them, card content, the card key, and the duplicate rule.

## Current decisions

### Surface and location

- The domain lives in `app/lib/deck/`; its public surface is `app/lib/deck/deck.dart`, with internals under `app/lib/deck/src/` ([ADR 0002](adr/0002-domain-public-surface-and-shared-database.md)).
- The surface exports:
  - the model: `Deck`, `Card`, `DeckId`, `CardId`, `CardSource`, `DeckVisibility` with `PrivateDeck` and `PublicDeck`, and `DeckSelection`, a set of decks that cannot be empty;
  - content: `Content`, `TextContent`, `ClozeContent` with `clozeBlank`, `TableContent` with `TableBlank`, `SensesContent` with `CardSense`, `SenseLabel`, `PartOfSpeechLabel`, `OtherLabel` and `PartOfSpeech`, `UnsupportedContent`, `decodeContent`, which reads the stored encoding, `decodeSense`, which reads one sense as the block and the extraction function write it, `plainText`, a side's text with its blanks filled, and `isWholeCard`, whether a front holds a cloze or a table;
  - `CardKey`, `describeContent`, the one line of text a card side shows, `spokenContent`, a side as a screen reader reads it, `CardSplitRow`, a card as a split row, and `CardBackRow`, a card's front with its back hidden or shown;
  - `WholeCardView`, which draws a whole card's front ([ADR 0068](adr/0068-store-a-table-or-cloze-card-as-typed-content-blocks-and-draw-it-whole-its-blanks-filled-in-place-once-answered.md));
  - `DeckRow`, a deck on a row, `DeckTile`, its icon on its colour, `showDeckAppearanceSheet`, the 덱 꾸미기 sheet, and `CardEditorScreen`, the card editor, with `deckStorageProvider` and `deckStorageKeys`, the device storage in which it keeps each deck's last card kind and the label presets; and `PartOfSpeechPresetsRow`, the settings row that opens the "품사 표시" screen, which `home/` gives the account screen ([ADR 0100](adr/0100-merge-the-word-kind-into-basic-type-each-sense-s-label-and-offer-the-user-s-labels-above-the-keyboard.md));
  - the split card, drawn one way for every screen: `SplitCard`, given each side as a `SideBuilder` of the width its text is laid out in, which lays out a card's two halves divided by a line, side by side or, when a half would be too narrow at the text scale, stacked, each side centred or at the top left and, on the study card, scrolling inside its half once capped; and `ContentView`, which renders a side's content blocks, with an unsupported block as a labelled placeholder, fitting text through `CardText` in `app/lib/deck/src/card_text.dart`, or, given a height too, running the blocks together as one paragraph scaled down as far as the floor until it fits that height and cut there with an ellipsis. The study screen's cards, the card preview and `CardSplitRow` draw through them ([ADR 0035](adr/0035-show-the-previous-and-current-study-card-reach-earlier-cards-three-at-a-time-re-decide-the-centred-card-and-grade-each-card-by-its-colour-and-a-chip.md), [ADR 0042](adr/0042-show-only-the-previous-and-the-current-study-card-at-one-size-re-decide-the-previous-card-by-a-swipe-and-open-it-on-a-tap.md));
  - `DeckRepository` and its save results;
  - the batch save of incoming cards, from a photo or a copy: `AddTarget`, `AddToDeck`, `AddToNewDeck`, `IncomingCard`, `DuplicateChoice`, `CardsAdded`, `mergeBack`, and `AddSource` with `FromPhoto` and `FromCopy`;
  - `showNameSheet`, the sheet that asks for a deck's name, which `home/` and photo import use to name a deck;
  - the failures: `DeckFailure`, `StorageFailure`, `UnreadableCard`, `DeckDeleted`, `describeFailure`, the message a user reads for one, `describeProviderError`, the same for an error a provider holds, and `reportingFailure`, which shows an action's failure in a snack bar;
  - `deckRepositoryProvider`, and the reads kept current over it: `decksProvider`, `cardCountsProvider`, `deckProvider` and `cardsProvider`.
- The `study` domain reads a deck's cards through `DeckRepository.listCards`, oldest first.

### Model

- A deck has an id, a name, creation and update times, a visibility, an optional description, and an optional icon and colour, `DeckIcon` and `DeckColor`, each stored as a key; a null key, or one this build does not know, reads as none ([ADR 0103](adr/0103-give-each-deck-an-icon-and-a-colour-stored-as-two-unchecked-keys-and-drawn-on-its-tile-in-place-of-the-initial.md)). The visibility is `PrivateDeck`, the default, or `PublicDeck` with its publish time ([`sharing.md`](sharing.md)).
- A card belongs to one deck and has a front, a back, a card key, a source, and creation and update times. Ids are UUIDs: new ones version 7, from the `uuid` package's `v7()`, which the composition site, `app/lib/main.dart`, passes to `DeckRepository` as `newId` ([ADR 0034](adr/0034-key-synced-rows-by-client-made-uuids-purge-tombstones-past-a-revision-horizon-and-index-each-query.md), [`sync.md`](sync.md)). Rows created before #124 (`2ad33491353dc8f4dfca12f906611a7c825ea3c0`, 2026-10-17), when it passed `v4()`, keep version 4 ids.
- `source` is `manual`, `import` or `copy`. The editor writes `manual`, photo import `import`, and a copy of another user's public deck `copy` ([ADR 0082](adr/0082-name-copying-a-public-deck-copy-and-keep-import-for-photo-import.md)), with the copied deck's id as `originDeckId`, null on every other card.
- Front and back are each an ordered list of content blocks. A block's type is `text`, `cloze`, `table` or `senses`, or `UnsupportedContent` stands for a stored type this version does not know ([ADR 0068](adr/0068-store-a-table-or-cloze-card-as-typed-content-blocks-and-draw-it-whole-its-blanks-filled-in-place-once-answered.md)):
  - a `cloze` block holds its text, which writes each blank as `___`, and its answers, one non-empty answer per blank, in order;
  - a `table` block holds its column headers, its rows, each as many cells as there are columns and starting with the row's header, and its blanks, each the row and column of a cell with text, distinct;
  - a `senses` block holds a vocabulary entry's senses, one or more, in the page's order, each a meaning, the labels the page prints for it in order and its examples; a label is a part of speech, one of fourteen with a fixed short form, or another label as printed ([ADR 0075](adr/0075-store-a-vocabulary-card-s-senses-as-a-typed-block-and-show-each-label-in-brackets-before-its-meaning.md));
  - a block that breaks its type's shape is unreadable, as a text block without text is.
- A whole card is a card whose front holds a cloze or a table block: a table card's front is a text block with the table's name, then the table; a cloze card's front is its cloze. Its back is one text block, the front's text with its blanks filled, which photo import and a copy write. It is one card, with one key and one state. v6's cloze cards, a text front with `___`, stay split text cards.
- A senses block's text is one line per sense, each label in brackets and one space before the meaning, a part of speech by its short form: `[명] [사물] 기차`. Search, a screen reader, a merged back and the card key read it. Drawn, through `sensesSpan`, which `contentSpan` and `ContentView` use for every side, each label is its own span with a gap of `AppSpace.s4` after it, the closing bracket's letter spacing, before the meaning, and a sense with no label shows its meaning alone ([ADR 0075](adr/0075-store-a-vocabulary-card-s-senses-as-a-typed-block-and-show-each-label-in-brackets-before-its-meaning.md)). The study cards, the card preview, `CardSplitRow` and `CardBackRow` draw every side through them.
- `WholeCardView` draws a whole card's front from its blocks: a text block as its title; a cloze in its caller's style, centred, fitted to a width as `CardText` fits; a table in the body size, its header row and each row's first cell bold, its header row on `ground`, inside `outline` lines; and, given a height, the whole front scaled down to fit it. An empty blank is its answer drawn in `hairline` on `hairline`, so filling it moves nothing; a filled one is the answer on `brandTint`. It reads as `spokenContent` says: each empty blank "빈칸", a table row by row, its cells joined by commas. Wherever a card is drawn split, a whole card is drawn whole through it: the study cards, `CardPreview` and `CardSplitRow` filled, and `CardBackRow` as below. `ContentView` draws a cloze or table block in a split side the same way, filled.

### Storage

- The tables `decks` and `cards` are this domain's, held in the shared database `app/lib/database/database.dart`. The `reviews` and `card_states` tables there belong to the `study` domain ([`study.md`](study.md)).
- Every write sets the row's `updated_at` and leaves it unsynced (`dirty`), for sync to push ([`sync.md`](sync.md)).
- `decks` holds `visibility` (`private` or `public`), `published_at` and `description`; `cards` holds `origin_deck_id`. `setVisibility` writes the first three; a private deck keeps its description for the next publish. A deleted deck refuses it with `DeckDeleted`.
- A card side is stored as a JSON array of blocks, each with a `type` discriminator and a `payload`. A new block type adds a discriminator value; stored rows need no migration, on the device or the server, whose columns hold any array ([ADR 0068](adr/0068-store-a-table-or-cloze-card-as-typed-content-blocks-and-draw-it-whole-its-blanks-filled-in-place-once-answered.md)).
- A stored block of an unknown type is read as `UnsupportedContent` and written back unchanged, so a card a later version wrote is shown, not lost.
- Deleting a deck sets `deleted_at` on it and on each of its cards, a tombstone sync pushes. The UI asks for confirmation first and states how many cards go with it.
- Deleting a card sets its `deleted_at`. Its reviews and state stay in the database, out of every screen. The editor asks for confirmation first.
- Every read leaves tombstoned decks and cards out: the lists, the counts, `listCards`, and the duplicate check.
- Every write is local. Nothing in the domain touches the network or imports `sync`.
- Stored vocabulary backs written as text with a printed label, such as `[명] 사과`, become senses blocks on the server (#228), by migration `20261019180003_senses_migration.sql` ([`server.md`](server.md), [ADR 0075](adr/0075-store-a-vocabulary-card-s-senses-as-a-typed-block-and-show-each-label-in-brackets-before-its-meaning.md)):
  - A card converts only when its back is one text block and every non-empty line is a sense line: a known short form, Korean or English (`명`, `동`, `n`, `adj` …), in brackets, in parentheses, with a dot, or bare and followed by a space and more text. Its back becomes one senses block, a sense per line, each labelled as the part of speech its short form names, with the label as printed.
  - A card with any other line is left alone, so a note or free text is never touched.
  - The rules are SQL functions the migration defines, `private.senses_block` and those it calls, and the dry run calls the same ones.
  - The dry run, `supabase/senses-dry-run.sh`, runs `supabase/senses-dry-run.sql` read-only against a running local stack, such as one holding a copy of production, and writes a report for the PM. The report counts the live cards, those that would convert and those left alone, by reason, and gives each form's cards, lines and up to five samples, every bare-form line, as its label may be a meaning's first word, and up to five mixed cards.
  - `supabase/senses-dry-run.test.sh`, in `make test`, checks it on a fixture of each form, a mixed card, a note, an unrecognised label, a back of two blocks and a deleted card, that no row changes, and that the migration then converts as many cards as the report counts.

### Card key and duplicates

- The card key is the front's text, a cloze's and a table's with their blanks filled (`plainText`), normalized in this order: Unicode NFKC, trim, collapse each whitespace run to one space, case-fold. Punctuation and accents are kept.
- Case-folding is Dart's lowercase mapping, which matches Unicode simple case folding; full folding such as `ß` to `ss` is not applied.
- A duplicate is another card in the same deck with an equal key. Cards in other decks are never duplicates.
- Adding or editing a card whose key collides is refused with the existing card, unless the caller allows the duplicate. The editor then opens a bottom sheet, "이 덱에 이미 있는 카드예요", which says that case and spacing are ignored, shows the existing card as a split card, and offers "기존 카드 열기", which opens the existing card over the editor so that closing it returns to the card being typed (issue #309), and, last, "그래도 추가" (or "그래도 저장" when editing); dismissing it does neither ([ADR 0024](adr/0024-one-voice-and-a-sheet-action-rule.md)). No card is overwritten or deleted by the rule.
- The check is one lookup on the `(deck_id, card_key)` index, inside the same transaction as the write.

### Import

- `DeckRepository.addCards` saves a list of `IncomingCard`s into an existing deck, or into a new deck it creates, in one transaction: a failure writes nothing, the new deck included.
- Each card's sides are content blocks, a table or cloze card's front kept as its blocks, and it is written unsynced like every write, with the source its `AddSource` gives: `import` from a photo, or `copy` and the origin deck from a public deck ([`sharing.md`](sharing.md)).
- An import into a deck deleted meanwhile, on this device or through sync, is refused with `DeckDeleted` and writes nothing.
- A card whose key collides with a card in the deck, or with one written earlier in the same import, does what its `DuplicateChoice` says, as the PM decided for issue #30:
  - **skip** (건너뛰기) writes nothing;
  - **merge back** (뒷면 합치기) appends the card's back to the existing card's back as a new text block, keeping its id, front and reviews; when a line of that back already equals it under the card key normalization, nothing changes;
  - **add as new** (새 카드로 추가) adds the card beside the existing one.
- No card is overwritten or deleted. The choice is per card; photo import gives every card it writes merge back, so a card whose key the deck holds, or one written earlier in the same import, is merged rather than doubled. It imports only the cards of the rows its list includes, each in its section's form, so a row left out is neither written nor merged ([`ai-extraction.md`](ai-extraction.md)).

### Failures

- Each expected failure has a type:
  - a colliding key is the save result `DuplicateFront`;
  - a block of an unknown type is `UnsupportedContent`;
  - a database exception is `StorageFailure`;
  - stored content that cannot be decoded is `UnreadableCard`. `addCard` and `editCard` read the row they wrote back inside their transaction, so content the decoder refuses fails the save as `UnreadableCard` and is never stored (issue #306);
  - a write into a deck that was deleted is `DeckDeleted`.
- `StorageFailure`, `UnreadableCard` and `DeckDeleted` are `DeckFailure`s the repository throws, or emits on a watched stream.
- The screens show a `DeckFailure` to the user as a localized message, in a snack bar for an action or in place of a list. Any other error propagates.

### Interface

- Every string the screens show comes from the shared ARB set.
- Every tap target carries a semantic label: its text, or a tooltip for an icon button.
- The screens follow the principles and the theme of [`design.md`](design.md). Widget tests check each screen against Flutter's `labeledTapTargetGuideline`, `androidTapTargetGuideline` and `textContrastGuideline` in the light and the dark theme.
- An empty deck name or card side is refused with a message on its field.

### Row

- `DeckRow` draws a deck on a rounded surface: its 44 px tile (`DeckTile`), hidden from screen readers beside the name; its name, a "공개" chip when it is public, and what its caller shows of today; and under them what its caller shows of its progress, or "카드 n장" without it. A tap opens the deck.
- `DeckTile` draws the deck's icon in ink, at half the tile's side, on its colour from the theme's deck palette. A deck with no icon this build knows shows `layers`; one with no colour it knows, the palette colour its id selects, `deckTintIndex(id, 6)`: the sum of the id's UTF-16 code units modulo the palette's six; the web app computes the same ([`web-decks.md`](web-decks.md), [ADR 0103](adr/0103-give-each-deck-an-icon-and-a-colour-stored-as-two-unchecked-keys-and-drawn-on-its-tile-in-place-of-the-initial.md)). The 덱 tab's rows, the 오늘 tab's "오늘 할 덱" rows and the deck page draw it.
- `showDeckAppearanceSheet` opens the sheet "덱 꾸미기": the deck's tile at twice its size, previewing the pair chosen, then "아이콘", the fourteen icons, and "색", the six colours, each a target 48 square on an outline, ringed in ink while chosen, read by its 한국어 name as a button selected or not; "저장" returns the pair, and a dismissal returns nothing. `DeckRepository.setAppearance` stores the pair, unsynced; a rename writes only the name, so a key this build does not know survives it.
- Its caller passes the card count as a value, what to show of today and of its progress as widgets, and the callbacks that open the deck and select it; the 덱 tab is that caller ([`home.md`](home.md)).
- `CardBackRow` draws a card's front on a rounded row with its back hidden behind a bar, or shown, as its owner says; a tap calls back for its owner to decide, so a screen can set every row at once (issue #142); a pencil at its end, an `IconButton` with the tooltip "카드 편집", calls back to edit it, as a long-press and the screen reader's "카드 편집" on the row do ([ADR 0095](adr/0095-give-each-card-row-on-the-deck-screen-a-pencil-that-opens-the-card-in-the-editor.md)). For a screen reader the row is two nodes, the toggle and the pencil. It is read as "{front}, 뒷면 가려짐" or "{front}, 뒷면 {back}" ([ADR 0036](adr/0036-organise-the-app-in-today-decks-and-record-tabs-and-define-the-daily-goal-forecast-and-card-progress.md)). A whole card's row shows its front through `WholeCardView` in place of the front and the bar, its blanks empty, filled where the back is shown, its front read with each blank "빈칸" ([ADR 0068](adr/0068-store-a-table-or-cloze-card-as-typed-content-blocks-and-draw-it-whole-its-blanks-filled-in-place-once-answered.md)).

### Card editor

- The editor's top bar has a close button, the title "카드 추가" or "카드 편집", and, when editing, a delete button. The deck name heads the form instead, after a layers icon, on one line cut with an ellipsis and read as "{deck} 덱", so a long name never pushes the title out (issue #310).
- **Kinds** ([ADR 0083](adr/0083-write-every-card-kind-by-hand-in-a-form-of-its-own-chosen-by-a-kind-switch-each-deck-remembers.md), [ADR 0100](adr/0100-merge-the-word-kind-into-basic-type-each-sense-s-label-and-offer-the-user-s-labels-above-the-keyboard.md)): a card is a cloze or a table when its front holds that block, and otherwise basic, a back of senses included.
  - A new card's editor opens with a segmented switch, "카드 종류", of "앞뒤", "빈칸" and "표", in the kind the deck's last new card was added in. It keeps that kind per deck on the device under `deckCardKinds`, written when a new card is saved; a tap on the switch alone, then leaving, keeps the kind it had (issue #311), and a stored word kind, from before ADR 0100, opens as basic. A write the device refuses shows a storage failure.
  - An existing card opens in its own kind, with no switch.
- A live preview shows the card as the study screen's previous card shows it, front left and back right, each centred in its half and shrunk until its widest word fits, as the study card does, its lines broken only between words (`keepWords`). Below it come the multi-line field "앞면" and the kind's form:
  - **basic:** the back, one meaning by default: a small label field, hinted "품사", beside the multi-line field "뒷면". "뜻 추가" adds a meaning under the last, which makes the back a list of senses, each a label field read as "뜻 n 품사" beside a field "뜻 n" ([ADR 0100](adr/0100-merge-the-word-kind-into-basic-type-each-sense-s-label-and-offer-the-user-s-labels-above-the-keyboard.md)).
    - A label is typed. Each word typed is one label, without the brackets a card shows it in: a part of speech where it is one of the fourteen short forms (`명`, `동` …), another label otherwise. A stored label opens as its short form, and keeps the text it was stored with while its field is left as it was.
    - While a label field has focus, a strip right above the keyboard, read as "품사 표시", offers the user's labels in their order, the one the field holds tinted `brandTint`; a tap fills the field with it, and the field keeps the focus. "관리" at its end opens the "품사 표시" screen.
    - With more than one sense, each has up, down and delete buttons under it, named "n번째 뜻을 위로", "n번째 뜻을 아래로" and "n번째 뜻 지우기", up and down disabled where they cannot act; deleting down to one makes it the back's one meaning again.
    - A sense stored with examples has its field "예문", one example per line.
    - Under the senses, each text block a back of senses holds beside them, such as photo import's extras or a merged back, has a multi-line field "덧붙인 내용" (issue #312).
  - **cloze:** the front is the line, its blanks drawn in it as blocks, their text on `brandTint` in ink, and the preview draws the card as its one face, each blank a block in place with its answer, an empty one as an empty block, from the first letter typed ([ADR 0101](adr/0101-edit-a-cloze-as-one-face-with-its-blanks-as-blocks-in-the-line-and-a-single-insert-blank-action.md)).
    - The form's one action sits in a bar right above the keyboard and follows the caret.
      - With the caret inside a blank, strictly between its ends or anywhere in the blank just opened, or a selection the blank holds, it reads "빈칸 풀기", named for a screen reader as "빈칸 풀기, {answer}" ("빈칸" while empty), and turns exactly that blank back into text.
      - Elsewhere it reads "빈칸 넣기". With characters selected in the line, it makes exactly them a blank, any run of characters, punctuation included, replacing the blanks it overlaps: `H₂O예요` blanks `H₂O`, `서울은` blanks `서울`. With none selected, it opens an empty blank at the cursor; what is typed there becomes its answer until the cursor leaves it, and one left empty goes.
    - No row under the line repeats the blanks; the blocks in it show them.
    - Blanks are spans of the line ([ADR 0092](adr/0092-make-each-chosen-cloze-word-a-blank-of-its-own-without-its-punctuation-narrowable-to-letters-and-keep-stored-blanks-through-an-edit.md)): a stored cloze opens with each blank where the card has it, and an edit to the line keeps every blank it leaves whole, before or after the changed part, and leaves out one it changes.
    - The form shows no count of its blanks and no line explaining them.
  - **table:** the front holds the table's name, its field labelled "앞면 · 표 이름", with the hint "표의 이름". Under it, a toolbar read as "표 도구", and the table in a grid of fixed-width cells that scrolls sideways, starting at two columns and two rows, with no mode switch ([ADR 0102](adr/0102-edit-a-table-in-its-cells-with-a-toolbar-over-it-and-no-mode-switch.md)).
    - Each header and cell is a field edited in place, the headers on `ground` and the headers and each row's first cell bold, read as "n열 머리글" or "n행 m열", and ", 빈칸" after it when it is a blank. A tap selects a cell and edits it; the keyboard's next moves to the next cell, and every edit stays in its cell. The selected cell is outlined in ink, and stays selected while a toolbar button is pressed.
    - The toolbar: "행 추가" and "열 추가" add one at the end; "빈칸", a toggle that shows whether the selected cell is a blank, makes it one or a plain cell again, and is offered on a body cell alone; "지우기" opens a menu of the selected cell's "n행 지우기" and "n열 지우기", a header's column alone, each disabled while one is left. Removing a row or column that holds text asks first through `showAppConfirm`, "n행을 지울까요?" or "n열을 지울까요?", "그 줄에 적은 내용도 함께 지워져요." and, last, "지우기". Removing moves the blanks with their cells and drops those removed.
    - A blank is drawn as a cell tinted `brandTint`.
    - The preview draws the table whole, its blanks filled.
- The editor is a scrolling column, so every field is built.
- On save, an empty front reads "내용을 입력하세요" under it, as does an empty back of one meaning, and a numbered sense without a meaning reads "뜻을 적어 주세요" under its field, a cloze with no blank holding text reads "빈칸을 하나 이상 넣어 주세요" under its blanks, a cloze line holding `___`, or a longer run of underscores, that would read as a blank with no answer "___는 빈칸 표시라 줄에 쓸 수 없어요" (issue #306), and a table with no blank "빈칸으로 할 칸을 하나 이상 골라 주세요" under its grid, or, with a blank on an empty cell, "빈칸으로 고른 칸에 내용을 적어 주세요", that cell outlined in `dontKnowText`; nothing is saved.
- A basic card saves its front as text. A back that held no senses, still one meaning with no label and no example, is saved as that meaning's text, as a basic back always was. Any other back is one senses block of its senses in order, each label as typed, the meaning trimmed and each non-empty example line trimmed, followed by every other block the card's back held, in its place: a text block of a back of senses as its "덧붙인 내용" field holds it, or left out once that field is cleared, the text of a back that held none being its first meaning, and a block of any other type as it was. Saved unchanged, it is stored as it was.
- A cloze saves a cloze block of the front, each blank that holds text `___` with the characters it covers as its answer, and the front filled as text as its back, as photo import writes one. Duplicates are keyed by the filled front. An existing cloze opens with each blank where the card has it, so saved unchanged it is stored as it was, and an edit elsewhere in its line keeps its blanks, a blank inside a word included (issue #308).
- A table saves its front as the name in a text block and then a table block of its headers and cells, each trimmed, and its blanks in the order chosen, and its back as the front's text, the name and then the table filled, as photo import writes one (issue #311). Duplicates are keyed by the name and the filled table. An existing table saved with its name and table unchanged is stored as it was, its back included whatever its shape, such as the table filled without the name, which the editor wrote before #311, or a copy's; once either is edited, its back is the front's text.
- Adding offers "저장", which saves and closes, and "저장하고 다음 카드", which saves and leaves the editor open and empty, in the same kind, with the focus on "앞면". Editing offers "저장" alone. The actions sit under the scrolling form in the screen's body rather than in its bottom bar, so with the keyboard up they stay above it on both platforms, and adding cards in a row with "저장하고 다음 카드" needs no step to hide the keyboard (issue #307).
- Leaving an editor in which anything was typed or chosen, by "닫기", Android's back or the iOS back swipe, asks first through `showAppConfirm`: "작성 중인 카드를 버릴까요?", "입력한 내용은 저장되지 않아요.", "계속 쓰기" and, last, "버리기". The route refuses the pop meanwhile, which also stops the iOS back swipe from starting. An editor with no change, a kind switch alone included, or one just reset by "저장하고 다음 카드", closes at once. No draft is stored (issue #309).
- A side holding a senses block in the basic form, a reversed word's front, keeps it while its field's text is left as it was. An edited one becomes a text block, its labels as typed, as "앞면을 고치면 [명] 같은 표시도 글자로 저장돼요." under the front says.

### Label presets

- The labels the strip above the keyboard offers are the user's, kept on the device under `labelPresets` as a list of a label and an optional name, in the user's order, and never synced ([ADR 0100](adr/0100-merge-the-word-kind-into-basic-type-each-sense-s-label-and-offer-the-user-s-labels-above-the-keyboard.md)). A device with none stored, or with a value it cannot read, starts from the fourteen short forms, each named, "명" as "명사" and so on.
- `PartOfSpeechPresetsRow`, "품사 표시" with a chevron, opens the "품사 표시" screen: "카드를 만들 때 키보드 위에 이 순서로 나와요." over the presets, each a row of a handle, its label on `ground` and its name, and a delete button named "{label} 지우기", with "표시 추가" under them.
  - A tap on a preset, read as "{label} {name} 고치기", edits it in place: a field "표시", a field "이름 (선택)" and "완료". An empty label reads "표시를 적어 주세요" under it; a preset just added and left empty goes.
  - The handle, named "{label} 순서 옮기기", moves its preset by a drag, or opens a menu of "위로" and "아래로", disabled where they cannot act, so no move needs a drag.
  - Every change is stored at once; a write the device refuses shows a storage failure.

### State and composition

- State and injection use Riverpod. `deckRepositoryProvider` has no implementation of its own; the composition site, `app/lib/main.dart`, overrides it with the repository it constructs.
- The domain imports no other domain. The home and deck screens that show its decks beside other domains' widgets are `home/`'s ([`home.md`](home.md), [ADR 0039](adr/0039-name-every-top-level-folder-by-its-responsibility-compose-across-domains-in-a-home-shell-and-keep-seams-off-screens.md)).
- The repository receives its clock and id generator, so tests fix both. It also streams each deck's card count, which the 덱 tab shows.

## Rationale

- [ADR 0095](adr/0095-give-each-card-row-on-the-deck-screen-a-pencil-that-opens-the-card-in-the-editor.md): why `CardBackRow` ends in a pencil that opens the editor, why the tap stays the toggle, and why the row draws its own ink.
- [ADR 0002](adr/0002-domain-public-surface-and-shared-database.md): why the surface is one library file and why the tables live in a shared database below the domains.
- [ADR 0009](adr/0009-multi-deck-session-and-random-queue-order.md): why a study session takes a `DeckSelection`.
- [ADR 0039](adr/0039-name-every-top-level-folder-by-its-responsibility-compose-across-domains-in-a-home-shell-and-keep-seams-off-screens.md): why the screens that show other domains beside the decks are `home/`'s, and why this domain declares no provider for another domain's screen.
- [ADR 0020](adr/0020-public-decks-in-a-sharing-domain.md): why a copy of a public deck is an import.
- [ADR 0068](adr/0068-store-a-table-or-cloze-card-as-typed-content-blocks-and-draw-it-whole-its-blanks-filled-in-place-once-answered.md): why a table or cloze card is typed content blocks rather than markup in the text or a new column, why no migration is needed, how it is drawn whole, and what happens to v6's cloze cards; issue #212 records the owner's request and the PM's direction.
- [ADR 0075](adr/0075-store-a-vocabulary-card-s-senses-as-a-typed-block-and-show-each-label-in-brackets-before-its-meaning.md): why a vocabulary card's senses are a typed block, the parts of speech and their short forms, how a label is drawn and read, and what the editor and a merged back do with it; issue #228 records the owner's decisions.
- [ADR 0027](adr/0027-draw-both-clients-in-the-smartman-brand-and-the-v2-screens.md): the v2 deck row, the card editor, and the deck tile's tint, whose initial and four tints [ADR 0103](adr/0103-give-each-deck-an-icon-and-a-colour-stored-as-two-unchecked-keys-and-drawn-on-its-tile-in-place-of-the-initial.md) replaced.
- [ADR 0103](adr/0103-give-each-deck-an-icon-and-a-colour-stored-as-two-unchecked-keys-and-drawn-on-its-tile-in-place-of-the-initial.md): why a deck's icon and colour are two keys no list checks, why a key this build does not know reads as the default, and why the palette has no green or red.
- Issue #4 records the model, the libraries, the normalization order, and the duplicate rule as decided by the PM. Issue #22 records the current screens, and issue #30 the import save and its duplicate options.
- [ADR 0015](adr/0015-sync-protocol-and-conflict-policy.md): why a delete is a tombstone and every write leaves its row unsynced.
- [ADR 0102](adr/0102-edit-a-table-in-its-cells-with-a-toolbar-over-it-and-no-mode-switch.md): why a table is edited in its cells, with a toolbar acting on the selected cell, and why the mode switch went.
- [ADR 0101](adr/0101-edit-a-cloze-as-one-face-with-its-blanks-as-blocks-in-the-line-and-a-single-insert-blank-action.md): why a cloze is edited in its line with one action, and why the word chips and "글자 고르기" went.
- [ADR 0100](adr/0100-merge-the-word-kind-into-basic-type-each-sense-s-label-and-offer-the-user-s-labels-above-the-keyboard.md): why the word kind is basic's, why a label is typed rather than picked, and why the labels offered are the user's own, kept on the device.

## Open questions

- Whether "case-fold" should mean full Unicode case folding (`ß` and `ss` equal) rather than the simple folding implemented. No card has needed it yet.
