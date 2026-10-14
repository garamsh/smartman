# Deck

The `deck` domain: decks, the cards inside them, card content, the card key, and the duplicate rule.

## Current decisions

### Surface and location

- The domain lives in `app/lib/deck/`; its public surface is `app/lib/deck/deck.dart`, with internals under `app/lib/deck/src/` ([ADR 0002](adr/0002-domain-public-surface-and-shared-database.md)).
- The surface exports:
  - the model: `Deck`, `Card`, `DeckId`, `CardId`, `CardSource`, and `DeckSelection`, a set of decks that cannot be empty;
  - content: `Content`, `TextContent`, `UnsupportedContent`;
  - `CardKey`, and `describeContent`, the one line of text a card side shows;
  - `DeckRepository` and its save results;
  - the failures: `DeckFailure`, `StorageFailure`, `UnreadableCard`, and `describeFailure`, the message a user reads for one;
  - `TodayCount`, with `TodayPending`, `TodayCounted` and `TodayUnavailable`, and `TodayBuilder`;
  - `deckRepositoryProvider`, `studyScreenProvider`, `todayProvider`, `accountScreenProvider`, `photoImportProvider` and `DeckListScreen`.
- The `study` domain reads a deck's cards through `DeckRepository.listCards`, oldest first.

### Model

- A deck has an id, a name, and creation and update times.
- A card belongs to one deck and has a front, a back, a card key, a source, and creation and update times. Ids are UUID v4 strings.
- `source` is `manual` or `import`. Only `manual` is written; `import` is reserved for photo import.
- Front and back are each an ordered list of content blocks. A block is `text`, or `UnsupportedContent` for a stored type this version does not know.

### Storage

- The tables `decks` and `cards` are this domain's, held in the shared database `app/lib/shared/database.dart`. The `reviews` and `card_states` tables there belong to the `study` domain ([`study.md`](study.md)); deleting a card deletes its rows in both through cascading foreign keys.
- A card side is stored as a JSON array of blocks, each with a `type` discriminator and a `payload`. A new block type adds a discriminator value; stored rows need no migration.
- A stored block of an unknown type is read as `UnsupportedContent` and written back unchanged, so a card a later version wrote is shown, not lost.
- Deleting a deck deletes its cards through a cascading foreign key. The UI asks for confirmation first and states how many cards go with it.
- Deleting a card deletes its study history. The editor asks for confirmation first.
- Every write is local. Nothing in the domain touches the network.

### Card key and duplicates

- The card key is the front's text normalized in this order: Unicode NFKC, trim, collapse each whitespace run to one space, case-fold. Punctuation and accents are kept.
- Case-folding is Dart's lowercase mapping, which matches Unicode simple case folding; full folding such as `ß` to `ss` is not applied.
- A duplicate is another card in the same deck with an equal key. Cards in other decks are never duplicates.
- Adding or editing a card whose key collides is refused with the existing card, unless the caller allows the duplicate. The editor then opens a bottom sheet, "이 덱에 이미 있는 카드예요", which says that case and spacing are ignored, shows the existing card as a split card, and offers "그래도 추가" (or "그래도 저장" when editing), "기존 카드 열기" and "취소". No card is overwritten or deleted by the rule.
- The check is one lookup on the `(deck_id, card_key)` index, inside the same transaction as the write.

### Failures

- Each expected failure has a type:
  - a colliding key is the save result `DuplicateFront`;
  - a block of an unknown type is `UnsupportedContent`;
  - a database exception is `StorageFailure`;
  - stored content that cannot be decoded is `UnreadableCard`.
- `StorageFailure` and `UnreadableCard` are `DeckFailure`s the repository throws, or emits on a watched stream.
- The screens show a `DeckFailure` to the user as a localized message, in a snack bar for an action or in place of a list. Any other error propagates.

### Interface

- Every string the screens show comes from the shared ARB set.
- Every tap target carries a semantic label: its text, or a tooltip for an icon button.
- The screens follow the principles and the theme of [`design.md`](design.md). Widget tests check each screen against Flutter's `labeledTapTargetGuideline`, `androidTapTargetGuideline` and `textContrastGuideline` in the light and the dark theme.
- An empty deck name or card side is refused with a message on its field.

### Deck list and selection

- The deck list has a large title, "덱", with the account button at its top right.
- Below it, a header card for a selection of every deck: "오늘 할 카드 n장", "복습 x · 새 카드 y", and "모두 학습", which opens one study session over every deck ([ADR 0009](adr/0009-multi-deck-session-and-random-queue-order.md)).
- "내 덱 n" labels the decks, with the hint "길게 눌러 여러 덱 선택".
- Each deck is a row on a rounded surface: its name, "카드 n장", a green "오늘 n" chip when a session over it would study n > 0 cards now, and a chevron. A count that cannot be read shows an icon whose tooltip says why.
- The bottom bar holds "새 덱", and "사진으로 만들기" once photo import exists.
- A tap opens a deck; a long-press enters selection mode with that deck selected.
- In selection mode:
  - a tap, or a long-press, adds or removes a deck;
  - the app bar shows how many decks are selected, a clear action that leaves the mode, and "학습 (n)", which opens one study session over the selected decks;
  - a deck deleted while selected leaves the selection, and "학습 (n)" is disabled while the selection is empty;
  - each deck's row exposes whether it is selected to screen readers.

### Card list

- The card list has a back button and a deck menu that renames or deletes the deck; deleting returns to the deck list.
- Below the large deck name, "카드 n장 · 오늘 복습 x · 새 카드 y", and a full-width green "학습 · n장", where n is the size of the session it opens, disabled at 0.
- A search field keeps the cards whose front or back text holds the search, ignoring case.
- Each card is a row of two columns, front and back, split by a thin divider; a tap opens it in the editor.
- The bottom bar holds "카드 추가", and "사진으로 추가" once photo import exists.

### Card editor

- The editor has a close button, the title "카드 추가" or "카드 편집", and the deck name on the right; when editing, also a delete button.
- A live preview shows the card as the study screen shows it with its answer revealed, question left and answer right, above the multi-line fields "문제" and "답".
- Adding offers "저장", which saves and closes, and "저장하고 다음 카드", which saves and leaves the editor open and empty with the focus on "문제". Editing offers "저장" alone.

### State and composition

- State and injection use Riverpod. `deckRepositoryProvider` has no implementation of its own; the composition site, `app/lib/main.dart`, overrides it with the repository it constructs.
- `studyScreenProvider` builds the screen that studies a `DeckSelection` in one session. The card list's "Study" button opens it for its own deck, and selection mode for the selected decks. It has no implementation of its own either: the composition site overrides it with the `study` domain's screen, so this domain does not depend on `study` ([ADR 0005](adr/0005-study-queue-and-card-state.md), [ADR 0009](adr/0009-multi-deck-session-and-random-queue-order.md)).
- `todayProvider` builds a widget that counts what a session over a `DeckSelection` would study now and shows the count, a `TodayCount`, through a builder this domain supplies. The header card, each row's chip and the card list's line and study button are such builders. The composition site overrides it with the `study` domain's `TodayCounter`, which reads the count and describes a failure ([ADR 0011](adr/0011-shared-app-theme-bundled-font-and-today-builder.md), [`study.md`](study.md)).
- `photoImportProvider` builds the photo import screen, for a deck or for a new one. It is null until the photo import feature (M6) exists, which hides both photo buttons; that feature overrides it.
- The deck list's account button opens the screen `accountScreenProvider` builds. The composition site overrides it with the `account` domain's screen, as it does `studyScreenProvider` ([`account.md`](account.md)).
- The repository receives its clock and id generator, so tests fix both. It also streams each deck's card count, which the deck list shows.

## Rationale

- [ADR 0002](adr/0002-domain-public-surface-and-shared-database.md): why the surface is one library file and why the tables live in a shared database below the domains.
- [ADR 0005](adr/0005-study-queue-and-card-state.md): why the study entry point is a provider the composition site overrides.
- [ADR 0009](adr/0009-multi-deck-session-and-random-queue-order.md): why the entry point takes a `DeckSelection`.
- [ADR 0011](adr/0011-shared-app-theme-bundled-font-and-today-builder.md): why the counts reach this domain through one builder provider rather than a function or a widget per place.
- Issue #4 records the model, the libraries, the normalization order, and the duplicate rule as decided by the PM. Issue #19 records the selection mode and the header card, and issue #22 the current screens.

## Open questions

- Whether "case-fold" should mean full Unicode case folding (`ß` and `ss` equal) rather than the simple folding implemented. No card has needed it yet.
