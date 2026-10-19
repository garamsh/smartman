# Deck

The `deck` domain: decks, the cards inside them, card content, the card key, and the duplicate rule.

## Current decisions

### Surface and location

- The domain lives in `app/lib/deck/`; its public surface is `app/lib/deck/deck.dart`, with internals under `app/lib/deck/src/` ([ADR 0002](adr/0002-domain-public-surface-and-shared-database.md)).
- The surface exports:
  - the model: `Deck`, `Card`, `DeckId`, `CardId`, `CardSource`, `DeckVisibility` with `PrivateDeck` and `PublicDeck`, and `DeckSelection`, a set of decks that cannot be empty;
  - content: `Content`, `TextContent`, `ClozeContent` with `clozeBlank`, `TableContent` with `TableBlank`, `UnsupportedContent`, `decodeContent`, which reads the stored encoding, `plainText`, a side's text with its blanks filled, and `isWholeCard`, whether a front holds a cloze or a table;
  - `CardKey`, `describeContent`, the one line of text a card side shows, `spokenContent`, a side as a screen reader reads it, `CardSplitRow`, a card as a split row, and `CardAnswerRow`, a card's question with its answer hidden or shown;
  - `WholeCardView`, which draws a whole card's front ([ADR 0068](adr/0068-store-a-table-or-cloze-card-as-typed-content-blocks-and-draw-it-whole-its-blanks-filled-in-place-once-answered.md));
  - `DeckRow`, a deck on a row, `DeckTile`, its initial on a tinted tile, and `CardEditorScreen`, the card editor;
  - the split card, drawn one way for every screen: `SplitCard`, given each side as a `SideBuilder` of the width its text is laid out in, which lays out a card's two halves divided by a line, side by side or, when a half would be too narrow at the text scale, stacked, each side centred or at the top left and, on the study card, scrolling inside its half once capped; and `ContentView`, which renders a side's content blocks, with an unsupported block as a labelled placeholder, fitting text through `CardText` in `app/lib/deck/src/card_text.dart`, or, given a height too, running the blocks together as one paragraph scaled down as far as the floor until it fits that height and cut there with an ellipsis. The study screen's cards, the card preview and `CardSplitRow` draw through them ([ADR 0035](adr/0035-show-the-previous-and-current-study-card-reach-earlier-cards-three-at-a-time-re-decide-the-centred-card-and-grade-each-card-by-its-colour-and-a-chip.md), [ADR 0042](adr/0042-show-only-the-previous-and-the-current-study-card-at-one-size-re-decide-the-previous-card-by-a-swipe-and-open-it-on-a-tap.md));
  - `DeckRepository` and its save results;
  - the import save: `ImportTarget`, `ImportIntoDeck`, `ImportIntoNewDeck`, `ImportedCard`, `DuplicateChoice`, `CardsImported`, `mergeBack`, and `ImportSource` with `FromPhoto` and `FromPublicDeck`;
  - `showNameSheet`, the sheet that asks for a deck's name, which `home/` and photo import use to name a deck;
  - the failures: `DeckFailure`, `StorageFailure`, `UnreadableCard`, `DeckDeleted`, `describeFailure`, the message a user reads for one, `describeProviderError`, the same for an error a provider holds, and `reportingFailure`, which shows an action's failure in a snack bar;
  - `deckRepositoryProvider`, and the reads kept current over it: `decksProvider`, `cardCountsProvider`, `deckProvider` and `cardsProvider`.
- The `study` domain reads a deck's cards through `DeckRepository.listCards`, oldest first.

### Model

- A deck has an id, a name, creation and update times, a visibility, and an optional description. The visibility is `PrivateDeck`, the default, or `PublicDeck` with its publish time ([`sharing.md`](sharing.md)).
- A card belongs to one deck and has a front, a back, a card key, a source, and creation and update times. Ids are UUID v4 strings. [ADR 0034](adr/0034-key-synced-rows-by-client-made-uuids-purge-tombstones-past-a-revision-horizon-and-index-each-query.md) makes new ones version 7, which is not built yet ([`sync.md`](sync.md)).
- `source` is `manual`, `import` or `shared`. The editor writes `manual`, photo import `import`, and a copy of another user's public deck `shared`, with the copied deck's id as `originDeckId`, null on every other card.
- Front and back are each an ordered list of content blocks. A block's type is `text`, `cloze` or `table`, or `UnsupportedContent` stands for a stored type this version does not know ([ADR 0068](adr/0068-store-a-table-or-cloze-card-as-typed-content-blocks-and-draw-it-whole-its-blanks-filled-in-place-once-answered.md)):
  - a `cloze` block holds its text, which writes each blank as `___`, and its answers, one non-empty answer per blank, in order;
  - a `table` block holds its column headers, its rows, each as many cells as there are columns and starting with the row's header, and its blanks, each the row and column of a cell with text, distinct;
  - a block that breaks its type's shape is unreadable, as a text block without text is.
- A whole card is a card whose front holds a cloze or a table block: a table card's front is a text block with the table's name, then the table; a cloze card's front is its cloze. Its back is one text block, the front's text with its blanks filled, which photo import and a copy write. It is one card, with one key and one state. v6's cloze cards, a text front with `___`, stay split text cards.
- `WholeCardView` draws a whole card's front from its blocks: a text block as its title; a cloze in its caller's style, centred, fitted to a width as `CardText` fits; a table in the body size, its header row and each row's first cell bold, its header row on `ground`, inside `outline` lines; and, given a height, the whole front scaled down to fit it. An empty blank is its answer drawn in `hairline` on `hairline`, so filling it moves nothing; a filled one is the answer on `brandTint`. It reads as `spokenContent` says: each empty blank "빈칸", a table row by row, its cells joined by commas. Wherever a card is drawn split, a whole card is drawn whole through it: the study cards, `CardPreview` and `CardSplitRow` filled, and `CardAnswerRow` as below. `ContentView` draws a cloze or table block in a split side the same way, filled.

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

### Card key and duplicates

- The card key is the front's text, a cloze's and a table's with their blanks filled (`plainText`), normalized in this order: Unicode NFKC, trim, collapse each whitespace run to one space, case-fold. Punctuation and accents are kept.
- Case-folding is Dart's lowercase mapping, which matches Unicode simple case folding; full folding such as `ß` to `ss` is not applied.
- A duplicate is another card in the same deck with an equal key. Cards in other decks are never duplicates.
- Adding or editing a card whose key collides is refused with the existing card, unless the caller allows the duplicate. The editor then opens a bottom sheet, "이 덱에 이미 있는 카드예요", which says that case and spacing are ignored, shows the existing card as a split card, and offers "기존 카드 열기" and, last, "그래도 추가" (or "그래도 저장" when editing); dismissing it does neither ([ADR 0024](adr/0024-one-voice-and-a-sheet-action-rule.md)). No card is overwritten or deleted by the rule.
- The check is one lookup on the `(deck_id, card_key)` index, inside the same transaction as the write.

### Import

- `DeckRepository.importCards` saves a list of `ImportedCard`s into an existing deck, or into a new deck it creates, in one transaction: a failure writes nothing, the new deck included.
- Each card's sides are content blocks, a table or cloze card's front kept as its blocks, and it is written unsynced like every write, with the source its `ImportSource` gives: `import` from a photo, or `shared` and the origin deck from a public deck ([`sharing.md`](sharing.md)).
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
  - stored content that cannot be decoded is `UnreadableCard`;
  - a write into a deck that was deleted is `DeckDeleted`.
- `StorageFailure`, `UnreadableCard` and `DeckDeleted` are `DeckFailure`s the repository throws, or emits on a watched stream.
- The screens show a `DeckFailure` to the user as a localized message, in a snack bar for an action or in place of a list. Any other error propagates.

### Interface

- Every string the screens show comes from the shared ARB set.
- Every tap target carries a semantic label: its text, or a tooltip for an icon button.
- The screens follow the principles and the theme of [`design.md`](design.md). Widget tests check each screen against Flutter's `labeledTapTargetGuideline`, `androidTapTargetGuideline` and `textContrastGuideline` in the light and the dark theme.
- An empty deck name or card side is refused with a message on its field.

### Row

- `DeckRow` draws a deck on a rounded surface: the name's first letter on a 44 px tile (`DeckTile`) in one of four tints, chosen from the deck's id so a deck keeps its tint and the web app picks the same one, hidden from screen readers beside the name; its name, a "공개" chip when it is public, and what its caller shows of today; and under them what its caller shows of its progress, or "카드 n장" without it. A tap opens the deck.
- Its caller passes the card count as a value, what to show of today and of its progress as widgets, and the callbacks that open the deck and select it; the 덱 tab is that caller ([`home.md`](home.md)).
- `CardAnswerRow` draws a card's question on a rounded row with its answer hidden behind a bar, or shown, as its owner says; a tap calls back for its owner to decide, so a screen can set every row at once (issue #142); a long-press, or the screen reader's "카드 편집", calls back to edit it. It is read as "{front}, 답 가려짐" or "{front}, 답 {back}" ([ADR 0036](adr/0036-organise-the-app-in-today-decks-and-record-tabs-and-define-the-daily-goal-forecast-and-card-progress.md)). A whole card's row shows its front through `WholeCardView` in place of the question and the bar, its blanks empty, filled where the answer is shown, its front read with each blank "빈칸" ([ADR 0068](adr/0068-store-a-table-or-cloze-card-as-typed-content-blocks-and-draw-it-whole-its-blanks-filled-in-place-once-answered.md)).

### Card editor

- The editor has a close button, the title "카드 추가" or "카드 편집", and the deck name on the right; when editing, also a delete button.
- A live preview shows the card as the study screen's previous card shows it, question left and answer right, each centred in its half and shrunk until its widest word fits, as the study card does, above the multi-line fields "문제" and "답".
- Adding offers "저장", which saves and closes, and "저장하고 다음 카드", which saves and leaves the editor open and empty with the focus on "문제". Editing offers "저장" alone.
- A whole card opens read-only ([ADR 0068](adr/0068-store-a-table-or-cloze-card-as-typed-content-blocks-and-draw-it-whole-its-blanks-filled-in-place-once-answered.md)): its preview filled, "표 카드와 빈칸 카드는 아직 고칠 수 없어요. 지울 수는 있어요." under it, no field and no "저장", and the delete button. A card the user types is a text card; there is no table editor.

### State and composition

- State and injection use Riverpod. `deckRepositoryProvider` has no implementation of its own; the composition site, `app/lib/main.dart`, overrides it with the repository it constructs.
- The domain imports no other domain. The home and deck screens that show its decks beside other domains' widgets are `home/`'s ([`home.md`](home.md), [ADR 0039](adr/0039-name-every-top-level-folder-by-its-responsibility-compose-across-domains-in-a-home-shell-and-keep-seams-off-screens.md)).
- The repository receives its clock and id generator, so tests fix both. It also streams each deck's card count, which the 덱 tab shows.

## Rationale

- [ADR 0002](adr/0002-domain-public-surface-and-shared-database.md): why the surface is one library file and why the tables live in a shared database below the domains.
- [ADR 0009](adr/0009-multi-deck-session-and-random-queue-order.md): why a study session takes a `DeckSelection`.
- [ADR 0039](adr/0039-name-every-top-level-folder-by-its-responsibility-compose-across-domains-in-a-home-shell-and-keep-seams-off-screens.md): why the screens that show other domains beside the decks are `home/`'s, and why this domain declares no provider for another domain's screen.
- [ADR 0020](adr/0020-public-decks-in-a-sharing-domain.md): why a copy of a public deck is an import.
- [ADR 0068](adr/0068-store-a-table-or-cloze-card-as-typed-content-blocks-and-draw-it-whole-its-blanks-filled-in-place-once-answered.md): why a table or cloze card is typed content blocks rather than markup in the text or a new column, why no migration is needed, how it is drawn whole, and what happens to v6's cloze cards; issue #212 records the owner's request and the PM's direction.
- [ADR 0027](adr/0027-draw-both-clients-in-the-smartman-brand-and-the-v2-screens.md): the v2 deck row, the card editor, and the deck tile's tint.
- Issue #4 records the model, the libraries, the normalization order, and the duplicate rule as decided by the PM. Issue #22 records the current screens, and issue #30 the import save and its duplicate options.
- [ADR 0015](adr/0015-sync-protocol-and-conflict-policy.md): why a delete is a tombstone and every write leaves its row unsynced.

## Open questions

- Whether "case-fold" should mean full Unicode case folding (`ß` and `ss` equal) rather than the simple folding implemented. No card has needed it yet.
