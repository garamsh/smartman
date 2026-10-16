import 'package:drift/drift.dart';

import 'database.steps.dart';

part 'database.g.dart';

/// Decks, each a named collection of cards, with whether it is published.
@DataClassName('DeckRow')
class Decks extends Table {
  TextColumn get id => text()();
  TextColumn get name => text()();
  TextColumn get visibility => text()
      .withDefault(const Constant('private'))
      .check(const CustomExpression("visibility IN ('private', 'public')"))();

  /// When the deck was last published; null while it never was, or once it
  /// was made private again.
  DateTimeColumn get publishedAt => dateTime().nullable()();
  TextColumn get description => text().nullable()();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();
  DateTimeColumn get deletedAt => dateTime().nullable()();
  BoolColumn get dirty => boolean().withDefault(const Constant(true))();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

/// Cards; `front` and `back` hold encoded content blocks, `cardKey` the
/// normalized front the duplicate check looks up.
@DataClassName('CardRow')
@TableIndex(name: 'cards_deck_id_card_key', columns: {#deckId, #cardKey})
class Cards extends Table {
  TextColumn get id => text()();
  TextColumn get deckId =>
      text().references(Decks, #id, onDelete: KeyAction.cascade)();
  TextColumn get front => text()();
  TextColumn get back => text()();
  TextColumn get cardKey => text()();
  TextColumn get source => text().check(
    const CustomExpression("source IN ('manual', 'import', 'shared')"),
  )();

  /// The public deck a copied card came from; null for any other card.
  TextColumn get originDeckId => text().nullable()();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();
  DateTimeColumn get deletedAt => dateTime().nullable()();
  BoolColumn get dirty => boolean().withDefault(const Constant(true))();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

/// Reviews of a card, written by the study domain.
@DataClassName('ReviewRow')
class Reviews extends Table {
  TextColumn get id => text()();
  TextColumn get cardId =>
      text().references(Cards, #id, onDelete: KeyAction.cascade)();
  TextColumn get rating =>
      text().check(const CustomExpression("rating IN ('again', 'good')"))();
  DateTimeColumn get reviewedAt => dateTime()();
  IntColumn get durationMs => integer()();

  /// The fuzz factor the review was scheduled with; null for a review written
  /// before schema v3, which was scheduled without fuzz.
  RealColumn get fuzzFactor => real().nullable().check(
    const CustomExpression('fuzz_factor >= 0 AND fuzz_factor < 1'),
  )();
  DateTimeColumn get updatedAt => dateTime()();
  DateTimeColumn get deletedAt => dateTime().nullable()();
  BoolColumn get dirty => boolean().withDefault(const Constant(true))();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

/// A reviewed card's scheduling state, owned by the study domain. A card that
/// was never reviewed has no row.
@DataClassName('CardStateRow')
class CardStates extends Table {
  TextColumn get cardId =>
      text().references(Cards, #id, onDelete: KeyAction.cascade)();
  RealColumn get stability => real()();
  RealColumn get difficulty => real()();
  DateTimeColumn get lastReview => dateTime()();
  DateTimeColumn get due => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();
  DateTimeColumn get deletedAt => dateTime().nullable()();
  BoolColumn get dirty => boolean().withDefault(const Constant(true))();

  @override
  Set<Column<Object>> get primaryKey => {cardId};
}

/// Which account the local database belongs to, and how far each synced table
/// has been pulled: the highest server revision seen. At most one row; none
/// while no account owns the database.
@DataClassName('SyncStateRow')
class SyncState extends Table {
  IntColumn get id => integer().check(const CustomExpression('id = 0'))();
  TextColumn get owner => text()();
  IntColumn get decksRevision => integer()();
  IntColumn get cardsRevision => integer()();
  IntColumn get reviewsRevision => integer()();
  IntColumn get cardStatesRevision => integer()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

/// The app's local SQLite database, shared by every domain below which it sits.
@DriftDatabase(tables: [Decks, Cards, Reviews, CardStates, SyncState])
class AppDatabase extends _$AppDatabase {
  AppDatabase(super.executor);

  @override
  int get schemaVersion => 5;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onUpgrade: stepByStep(
      from1To2: (m, schema) async {
        await m.createTable(schema.cardStates);
      },
      from2To3: (m, schema) async {
        await m.addColumn(schema.reviews, schema.reviews.fuzzFactor);
      },
      // Every row from before v4 is unsynced, so the new dirty flags start set.
      from3To4: (m, schema) async {
        for (final (table, deletedAt, dirty) in [
          (schema.decks, schema.decks.deletedAt, schema.decks.dirty),
          (schema.cards, schema.cards.deletedAt, schema.cards.dirty),
        ]) {
          await m.addColumn(table, deletedAt);
          await m.addColumn(table, dirty);
        }
        await m.alterTable(
          TableMigration(
            schema.reviews,
            columnTransformer: {
              schema.reviews.updatedAt: schema.reviews.reviewedAt,
            },
            newColumns: [
              schema.reviews.updatedAt,
              schema.reviews.deletedAt,
              schema.reviews.dirty,
            ],
          ),
        );
        await m.alterTable(
          TableMigration(
            schema.cardStates,
            columnTransformer: {
              schema.cardStates.updatedAt: schema.cardStates.lastReview,
            },
            newColumns: [
              schema.cardStates.updatedAt,
              schema.cardStates.deletedAt,
              schema.cardStates.dirty,
            ],
          ),
        );
        await m.createTable(schema.syncState);
      },
      // The cards table is rebuilt, since SQLite cannot change its source check
      // in place; foreign keys are off during migrations, so no review cascades.
      from4To5: (m, schema) async {
        await m.addColumn(schema.decks, schema.decks.visibility);
        await m.addColumn(schema.decks, schema.decks.publishedAt);
        await m.addColumn(schema.decks, schema.decks.description);
        await m.alterTable(
          TableMigration(schema.cards, newColumns: [schema.cards.originDeckId]),
        );
      },
    ),
    // SQLite leaves foreign keys off per connection; deck deletion cascades only with them on.
    beforeOpen: (details) async {
      await customStatement('PRAGMA foreign_keys = ON');
    },
  );
}
