import 'package:drift/drift.dart';

import 'database.steps.dart';

part 'database.g.dart';

/// Decks, each a named collection of cards.
@DataClassName('DeckRow')
class Decks extends Table {
  TextColumn get id => text()();
  TextColumn get name => text()();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();

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
  TextColumn get source =>
      text().check(const CustomExpression("source IN ('manual', 'import')"))();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();

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

  @override
  Set<Column<Object>> get primaryKey => {cardId};
}

/// The app's local SQLite database, shared by every domain below which it sits.
@DriftDatabase(tables: [Decks, Cards, Reviews, CardStates])
class AppDatabase extends _$AppDatabase {
  AppDatabase(super.executor);

  @override
  int get schemaVersion => 3;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onUpgrade: stepByStep(
      from1To2: (m, schema) async {
        await m.createTable(schema.cardStates);
      },
      from2To3: (m, schema) async {
        await m.addColumn(schema.reviews, schema.reviews.fuzzFactor);
      },
    ),
    // SQLite leaves foreign keys off per connection; deck deletion cascades only with them on.
    beforeOpen: (details) async {
      await customStatement('PRAGMA foreign_keys = ON');
    },
  );
}
