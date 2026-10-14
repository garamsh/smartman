import 'package:drift/drift.dart';

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

/// Reviews of a card. Defined for the study domain; nothing writes it yet.
@DataClassName('ReviewRow')
class Reviews extends Table {
  TextColumn get id => text()();
  TextColumn get cardId =>
      text().references(Cards, #id, onDelete: KeyAction.cascade)();
  TextColumn get rating =>
      text().check(const CustomExpression("rating IN ('again', 'good')"))();
  DateTimeColumn get reviewedAt => dateTime()();
  IntColumn get durationMs => integer()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

/// The app's local SQLite database, shared by every domain below which it sits.
@DriftDatabase(tables: [Decks, Cards, Reviews])
class AppDatabase extends _$AppDatabase {
  AppDatabase(super.executor);

  @override
  int get schemaVersion => 1;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    // SQLite leaves foreign keys off per connection; deck deletion cascades only with them on.
    beforeOpen: (details) async {
      await customStatement('PRAGMA foreign_keys = ON');
    },
  );
}
