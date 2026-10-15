# Deck

The `deck` domain: decks, the cards inside them, card content, the card key, and the duplicate rule.

## Current decisions

### Surface and location

- The domain lives in `app/lib/deck/`; its public surface is `app/lib/deck/deck.dart`, with internals under `app/lib/deck/src/` ([ADR 0002](adr/0002-domain-public-surface-and-shared-database.md)).
- The surface exports:
  - the model: `Deck`, `Card`, `DeckId`, `CardId`, `CardSource`, `DeckVisibility` with `PrivateDeck` and `PublicDeck`, and `DeckSelection`, a set of decks that cannot be empty;
  - content: `Content`, `TextContent`, `UnsupportedContent`, and `decodeContent`, which reads the stored encoding;
  - `CardKey`, `describeContent`, the one line of text a card side shows, and `CardSplitRow`, a card as a split row;
  - `DeckRepository` and its save results;
  - the import save: `ImportTarget`, `ImportIntoDeck`, `ImportIntoNewDeck`, `ImportedCard`, `DuplicateChoice`, `CardsImported`, `mergeBack`, and `ImportSource` with `FromPhoto` and `FromPublicDeck`;
  - `showNameSheet`, the sheet that asks for a deck's name, which photo import uses to name a new deck;
  - the failures: `DeckFailure`, `StorageFailure`, `UnreadableCard`, `DeckDeleted`, and `describeFailure`, the message a user reads for one;
  - `TodayCount`, with `TodayPending`, `TodayCounted`, which carries the time one card takes and the minutes the session takes, and `TodayUnavailable`, and `TodayBuilder`;
  - `DeckSharing` and `deckSharingProvider`;
  - `deckRepositoryProvider`, `studyScreenProvider`, `todayProvider`, `accountScreenProvider`, `accountAvatarProvider`, `photoImportProvider` and `DeckListScreen`.
- The `study` domain reads a deck's cards through `DeckRepository.listCards`, oldest first.

### Model

- A deck has an id, a name, creation and update times, a visibility, and an optional description. The visibility is `PrivateDeck`, the default, or `PublicDeck` with its publish time ([`sharing.md`](sharing.md)).
- A card belongs to one deck and has a front, a back, a card key, a source, and creation and update times. Ids are UUID v4 strings.
- `source` is `manual`, `import` or `shared`. The editor writes `manual`, photo import `import`, and a copy of another user's public deck `shared`, with the copied deck's id as `originDeckId`, null on every other card.
- Front and back are each an ordered list of content blocks. A block is `text`, or `UnsupportedContent` for a stored type this version does not know.

### Storage

- The tables `decks` and `cards` are this domain's, held in the shared database `app/lib/shared/database.dart`. The `reviews` and `card_states` tables there belong to the `study` domain ([`study.md`](study.md)).
- Every write sets the row's `updated_at` and leaves it unsynced (`dirty`), for sync to push ([`sync.md`](sync.md)).
- `decks` holds `visibility` (`private` or `public`), `published_at` and `description`; `cards` holds `origin_deck_id`. `setVisibility` writes the first three; a private deck keeps its description for the next publish. A deleted deck refuses it with `DeckDeleted`.
- A card side is stored as a JSON array of blocks, each with a `type` discriminator and a `payload`. A new block type adds a discriminator value; stored rows need no migration.
- A stored block of an unknown type is read as `UnsupportedContent` and written back unchanged, so a card a later version wrote is shown, not lost.
- Deleting a deck sets `deleted_at` on it and on each of its cards, a tombstone sync pushes. The UI asks for confirmation first and states how many cards go with it.
- Deleting a card sets its `deleted_at`. Its reviews and state stay in the database, out of every screen. The editor asks for confirmation first.
- Every read leaves tombstoned decks and cards out: the lists, the counts, `listCards`, and the duplicate check.
- Every write is local. Nothing in the domain touches the network or imports `sync`.

### Card key and duplicates

- The card key is the front's text normalized in this order: Unicode NFKC, trim, collapse each whitespace run to one space, case-fold. Punctuation and accents are kept.
- Case-folding is Dart's lowercase mapping, which matches Unicode simple case folding; full folding such as `ß` to `ss` is not applied.
- A duplicate is another card in the same deck with an equal key. Cards in other decks are never duplicates.
- Adding or editing a card whose key collides is refused with the existing card, unless the caller allows the duplicate. The editor then opens a bottom sheet, "이 덱에 이미 있는 카드예요", which says that case and spacing are ignored, shows the existing card as a split card, and offers "기존 카드 열기" and, last, "그래도 추가" (or "그래도 저장" when editing); dismissing it does neither ([ADR 0024](adr/0024-one-voice-and-a-sheet-action-rule.md)). No card is overwritten or deleted by the rule.
- The check is one lookup on the `(deck_id, card_key)` index, inside the same transaction as the write.

### Import

- `DeckRepository.importCards` saves a list of `ImportedCard`s into an existing deck, or into a new deck it creates, in one transaction: a failure writes nothing, the new deck included.
- Each card is plain text on both sides and is written unsynced like every write, with the source its `ImportSource` gives: `import` from a photo, or `shared` and the origin deck from a public deck ([`sharing.md`](sharing.md)).
- An import into a deck deleted meanwhile, on this device or through sync, is refused with `DeckDeleted` and writes nothing.
- A card whose key collides with a card in the deck, or with one written earlier in the same import, does what its `DuplicateChoice` says, as the PM decided for issue #30:
  - **skip** (건너뛰기) writes nothing;
  - **merge back** (뒷면 합치기) appends the card's back to the existing card's back as a new text block, keeping its id, front and reviews; when a line of that back already equals it under the card key normalization, nothing changes;
  - **add as new** (새 카드로 추가) adds the card beside the existing one.
- No card is overwritten or deleted. The choice is per card; photo import defaults each colliding card to skip, and gives the others merge back, so one written earlier in the same import is merged rather than doubled.

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

### Deck list and selection

- The deck list's top bar holds the horizontal lockup, 30 high and read as the app's name, as its heading; at its right, with sharing, a "둘러보기" icon button that opens the browse screen, then the account button, the account's initial in a 32 px circle ([ADR 0027](adr/0027-draw-both-clients-in-the-smartman-brand-and-the-v2-screens.md)).
- Below it, the today card for a selection of every deck, on the brand's navy (the raised surface in the dark theme) with the symbol faint in its corner: "오늘 할 카드", the count large with "장", "복습 x · 새 카드 y · 약 m분", and a white "모두 학습" with a play icon, which opens one study session over every deck ([ADR 0009](adr/0009-multi-deck-session-and-random-queue-order.md)). The minutes are the count times the time one card takes, which `study` reads from the user's latest reviews ([`study.md`](study.md)), rounded up.
- "내 덱 n" labels the decks, with the hint "길게 눌러 여러 덱 선택".
- Each deck is a row on a rounded surface: the name's first letter on a 44 px tile in one of four tints, chosen from the deck's id so a deck keeps its tint and the web app picks the same one; its name and "카드 n장"; a "공개" chip when it is public; a brand-tint "오늘 n" chip when a session over it would study n > 0 cards now; and a chevron. A count that cannot be read shows an icon whose tooltip says why.
- The bottom bar holds "새 덱", and "사진으로 만들기" when photo import exists. A photo import that saved opens the deck it saved into.
- Before the first deck, the list is the first-run home in place of the today card, the rows and the bottom bar: the mascot in a white circle, "첫 덱을 만들어 볼까요?", one line on how to start, then "사진으로 만들기" when photo import exists, "직접 만들기", which opens the new-deck sheet, and "공개 덱 둘러보기" with sharing.
- The new-deck sheet is titled "새 덱 만들기" with "이름은 나중에도 바꿀 수 있어요." under it, a "덱 이름" field, and "만들기".
- A tap opens a deck; a long-press enters selection mode with that deck selected.
- In selection mode:
  - a tap, or a long-press, adds or removes a deck;
  - the app bar shows how many decks are selected, a clear action that leaves the mode, and "학습 (n)", which opens one study session over the selected decks;
  - a deck deleted while selected leaves the selection, and "학습 (n)" is disabled while the selection is empty;
  - each deck's row exposes whether it is selected to screen readers.

### Card list

- The card list has a back button and a deck menu that renames or deletes the deck; deleting returns to the deck list. With sharing, the menu also offers "공개하기" or "비공개로 전환", disabled with a one-line reason while offline, and a public deck shows a "공개" chip beside its name.
- Below the deck name, at 26/800, three white pills, "카드 n", "복습 x" and "새 카드 y", and the primary "학습하기 · n장" with a play icon, where n is the size of the session it opens, disabled at 0.
- A 48 px search field keeps the cards whose front or back text holds the search, ignoring case.
- The cards are one white rounded group, a row each with one-pixel separators: front and back in two columns split by a thin divider, the back in the quieter ink; a tap opens it in the editor.
- The bottom bar holds "카드 추가", and "사진으로 추가" when photo import exists, both secondary. A photo import that saved into another deck replaces this list with that deck's; one into this deck returns here.

### Card editor

- The editor has a close button, the title "카드 추가" or "카드 편집", and the deck name on the right; when editing, also a delete button.
- A live preview shows the card as the study screen shows it with its answer revealed, question left and answer right, each centred vertically in its half, above the multi-line fields "문제" and "답".
- Adding offers "저장", which saves and closes, and "저장하고 다음 카드", which saves and leaves the editor open and empty with the focus on "문제". Editing offers "저장" alone.

### State and composition

- State and injection use Riverpod. `deckRepositoryProvider` has no implementation of its own; the composition site, `app/lib/main.dart`, overrides it with the repository it constructs.
- `studyScreenProvider` builds the screen that studies a `DeckSelection` in one session. The card list's "Study" button opens it for its own deck, and selection mode for the selected decks. It has no implementation of its own either: the composition site overrides it with the `study` domain's screen, so this domain does not depend on `study` ([ADR 0005](adr/0005-study-queue-and-card-state.md), [ADR 0009](adr/0009-multi-deck-session-and-random-queue-order.md)).
- `todayProvider` builds a widget that counts what a session over a `DeckSelection` would study now and shows the count, a `TodayCount`, through a builder this domain supplies. The header card, each row's chip and the card list's line and study button are such builders. The composition site overrides it with the `study` domain's `TodayCounter`, which reads the count and describes a failure ([ADR 0011](adr/0011-shared-app-theme-bundled-font-and-today-builder.md), [`study.md`](study.md)).
- `photoImportProvider` builds the photo import screen, for a deck or for a new one; the screen pops with the `Deck` it saved into. Null hides both photo buttons. The composition site overrides it with the `photo_import` domain's `PhotoImportScreen` ([`ai-extraction.md`](ai-extraction.md)), so this domain does not depend on that one.
- `deckSharingProvider` holds the `DeckSharing` the screens use to browse, publish and unpublish, and to know whether the device is online; null hides those entries. The composition site overrides it with the `sharing` domain's `SharingService` ([`sharing.md`](sharing.md), [ADR 0020](adr/0020-public-decks-in-a-sharing-domain.md)), so this domain does not depend on that one.
- The deck list's account button shows the widget `accountAvatarProvider` builds and opens the screen `accountScreenProvider` builds. The composition site overrides both with the `account` domain's, as it does `studyScreenProvider` ([`account.md`](account.md)).
- The repository receives its clock and id generator, so tests fix both. It also streams each deck's card count, which the deck list shows.

## Rationale

- [ADR 0002](adr/0002-domain-public-surface-and-shared-database.md): why the surface is one library file and why the tables live in a shared database below the domains.
- [ADR 0005](adr/0005-study-queue-and-card-state.md): why the study entry point is a provider the composition site overrides.
- [ADR 0009](adr/0009-multi-deck-session-and-random-queue-order.md): why the entry point takes a `DeckSelection`.
- [ADR 0011](adr/0011-shared-app-theme-bundled-font-and-today-builder.md): why the counts reach this domain through one builder provider rather than a function or a widget per place.
- [ADR 0020](adr/0020-public-decks-in-a-sharing-domain.md): why sharing reaches this domain's screens through one provider, and why a copy is an import.
- [ADR 0027](adr/0027-draw-both-clients-in-the-smartman-brand-and-the-v2-screens.md): the v2 deck screens, the today card's minutes, and the deck tile's tint.
- Issue #4 records the model, the libraries, the normalization order, and the duplicate rule as decided by the PM. Issue #19 records the selection mode and the header card, issue #22 the current screens, and issue #30 the import save and its duplicate options.
- [ADR 0015](adr/0015-sync-protocol-and-conflict-policy.md): why a delete is a tombstone and every write leaves its row unsynced.

## Open questions

- Whether "case-fold" should mean full Unicode case folding (`ß` and `ss` equal) rather than the simple folding implemented. No card has needed it yet.
