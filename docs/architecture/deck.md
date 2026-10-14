# Deck

The `deck` domain: decks, the cards inside them, card content, the card key, and the duplicate rule.

## Current decisions

### Surface and location

- The domain lives in `app/lib/deck/`; its public surface is `app/lib/deck/deck.dart`, with internals under `app/lib/deck/src/` ([ADR 0002](adr/0002-domain-public-surface-and-shared-database.md)).
- The surface exports:
  - the model: `Deck`, `Card`, `DeckId`, `CardId`, `CardSource`;
  - content: `Content`, `TextContent`, `UnsupportedContent`;
  - `CardKey`;
  - `DeckRepository` and its save results;
  - the failures: `DeckFailure`, `StorageFailure`, `UnreadableCard`;
  - `deckRepositoryProvider` and `DeckListScreen`.

### Model

- A deck has an id, a name, and creation and update times.
- A card belongs to one deck and has a front, a back, a card key, a source, and creation and update times. Ids are UUID v4 strings.
- `source` is `manual` or `import`. Only `manual` is written; `import` is reserved for photo import.
- Front and back are each an ordered list of content blocks. A block is `text`, or `UnsupportedContent` for a stored type this version does not know.

### Storage

- The tables `decks` and `cards` are this domain's, held in the shared database `app/lib/shared/database.dart`. The `reviews` table there belongs to the `study` domain; nothing writes it yet.
- A card side is stored as a JSON array of blocks, each with a `type` discriminator and a `payload`. A new block type adds a discriminator value; stored rows need no migration.
- A stored block of an unknown type is read as `UnsupportedContent` and written back unchanged, so a card a later version wrote is shown, not lost.
- Deleting a deck deletes its cards through a cascading foreign key. The UI asks for confirmation first and states how many cards go with it.
- Every write is local. Nothing in the domain touches the network.

### Card key and duplicates

- The card key is the front's text normalized in this order: Unicode NFKC, trim, collapse each whitespace run to one space, case-fold. Punctuation and accents are kept.
- Case-folding is Dart's lowercase mapping, which matches Unicode simple case folding; full folding such as `ß` to `ss` is not applied.
- A duplicate is another card in the same deck with an equal key. Cards in other decks are never duplicates.
- Adding or editing a card whose key collides is refused with the existing card, unless the caller allows the duplicate. The editor then offers to open the existing card or to save anyway. No card is overwritten or deleted by the rule.
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
- Every tap target carries a semantic label: its text, or a tooltip for an icon button. A widget test checks each screen against Flutter's `labeledTapTargetGuideline`.
- An empty deck name or card side is refused with a message on its field.

### State and composition

- State and injection use Riverpod. `deckRepositoryProvider` has no implementation of its own; the composition site, `app/lib/main.dart`, overrides it with the repository it constructs.
- The repository receives its clock and id generator, so tests fix both.

## Rationale

- [ADR 0002](adr/0002-domain-public-surface-and-shared-database.md): why the surface is one library file and why the tables live in a shared database below the domains.
- Issue #4 records the model, the libraries, the normalization order, and the duplicate rule as decided by the PM.

## Open questions

- Whether "case-fold" should mean full Unicode case folding (`ß` and `ss` equal) rather than the simple folding implemented. No card has needed it yet.
