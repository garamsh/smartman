# ADR 0082: Name copying a public deck "copy", and keep "import" for photo import

> Status: accepted
> Date: 2026-10-19

Append-only: once merged, the body below is not rewritten. A fact later found wrong is corrected in an appended note, not edited out; a revised decision is a new ADR that supersedes this one.

## Context

- Issue #218, read on `main` at `3df760f83b743317cc4ab9fa4fe8fd5dddea443f`, found that one action, copying another user's public deck, had three names:
  - "copy": `sharing.md`, `CopyTarget`, and the English strings;
  - "import": the table `deck_imports`, the column `decks.import_count`, the function `record_deck_import`, `PublicDeckSummary.importCount`, `ImportSource.FromPublicDeck` and the ARB keys of the copy sheet;
  - "shared": the stored value `cards.source = 'shared'` of a copied card.
- "import" also named photo import: `cards.source = 'import'`, `FromPhoto` and the `photo_import` domain. So `source = 'import'` marked a photo's card, while `deck_imports` and `import_count` counted copies.
- `deck`'s save of a batch of cards, `importCards` with its types, served both photo import and copying.
- `docs/convention/style.md` §Naming consistency: "Same concept, same name".
- Per [ADR 0078](0078-keep-no-older-app-or-function-build-working-until-the-first-store-release.md), no older app build need keep working, so a stored value can change in place.

## Decision

- **Copying a public deck is "copy"** in the database, the app, the web and the docs.
- **"import" is photo import alone**: `cards.source = 'import'`, `FromPhoto`, the `photo_import` domain and its strings.
- **A card's origin** keeps the column `cards.source`, now `manual`, `import` or `copy`.
- Renamed, in place and with no row lost, by migration `20261019230002_name_public_deck_copies.sql` and app schema v8:
  - the table `deck_imports` to `deck_copies`, with its keys `deck_copies_pkey`, `deck_copies_deck_id_fkey` and `deck_copies_user_id_fkey`, and its index `deck_copies_user_id`;
  - the column `decks.import_count` to `copy_count`, with its check `decks_copy_count_check`;
  - the function `record_deck_import(uuid)` to `record_deck_copy(uuid)`;
  - the count's returned column in `list_public_decks`, `admin_public_decks`, `admin_deck` and `admin_user_deck`, recreated with the same bodies and privileges;
  - a copied card's `source` from `shared` to `copy`, on the server and on the device, in both checks that name it, `cards_source_check` and `cards_origin_deck_id_check`.
- Renamed in the app:
  - `CardSource.shared` to `CardSource.copy`;
  - `PublicDeckSummary.importCount` to `copyCount`;
  - `SharingServer.recordImport` to `recordCopy`;
  - `import_sheet.dart` to `copy_sheet.dart`, with `showImportSheet` to `showCopySheet`;
  - the ARB keys `importToMyDecks`, `importAsNewDeck`, `importIntoExistingDeck`, `importNewDeckHint`, `importTargetDeck`, `importDuplicates` and `importConfirm` to `copy…`. Their Korean and English text stays as it is; the user-facing words are #207's.
- **`deck`'s batch save takes a neutral name**, since it serves both: `importCards` to `addCards`, `ImportTarget` to `AddTarget`, `ImportIntoDeck` to `AddToDeck`, `ImportIntoNewDeck` to `AddToNewDeck`, `ImportedCard` to `IncomingCard`, `CardsImported` to `CardsAdded`, and `ImportSource` to `AddSource` with `FromPhoto` and `FromCopy`. `card_import.dart` becomes `add_cards.dart`.
- Renamed in the web: the admin reads `copy_count`.
- **Kept**, each for its reason:
  - `cards.source = 'import'` and the `photo_import` domain, its screens, strings and `importFromPhoto`, which are photo import;
  - `list_public_decks`' sort value `copied`, already the copy name;
  - the earlier migration files `20261016090000_deck_imports.sql` and those that create or reference `deck_imports`, `import_count` and `record_deck_import`, since migrations are applied history and are never edited;
  - `shared` in the v5 and v6 fixtures of `app/test/drift/app_database/migration_test.dart` and in the generated schema dumps for v5 to v7, which record those versions as they were.

## Consequences

- One name per concept: a reader of `source = 'import'` knows it is a photo's card, and every count of copies says "copy".
- The remap changes each copied card's row on the server: it takes a new revision, so devices pull it, and its edit time stays. The device's schema v8 remaps its own rows without marking them unsynced.
- An app built before schema v8 refuses a pulled `copy` value in its check, and calls a function that no longer exists to copy. ADR 0078 accepts that before the first store release.

## Signs the decision was wrong

- A later feature needs "import" for something other than photo import, and the term has to be split again.
- "copy" is found to mean two things, such as copying a card within one's own decks, without a name of its own.
