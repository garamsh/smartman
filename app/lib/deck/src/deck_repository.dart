import 'package:drift/drift.dart';

import '../../shared/database.dart';
import 'card_key.dart';
import 'content.dart';
import 'model.dart';

/// The outcome of saving a card.
sealed class SaveCardResult {
  const SaveCardResult();
}

/// The card was stored.
final class CardSaved extends SaveCardResult {
  const CardSaved(this.card);

  final Card card;
}

/// Nothing was stored: [existing] in the same deck already has the card key.
final class DuplicateFront extends SaveCardResult {
  const DuplicateFront(this.existing);

  final Card existing;
}

/// Reads and writes decks and cards in the local database.
class DeckRepository {
  DeckRepository(this._db, {required this._clock, required this._newId});

  final AppDatabase _db;
  final DateTime Function() _clock;
  final String Function() _newId;

  /// Every deck, ordered by name, re-emitted on each change.
  Stream<List<Deck>> watchDecks() {
    final query = _db.select(_db.decks)
      ..orderBy([(deck) => OrderingTerm.asc(deck.name)]);
    return query.watch().map((rows) => rows.map(_toDeck).toList());
  }

  Future<Deck> createDeck(String name) async {
    final now = _clock();
    final row = DeckRow(
      id: _newId(),
      name: name,
      createdAt: now,
      updatedAt: now,
    );
    await _db.into(_db.decks).insert(row);
    return _toDeck(row);
  }

  Future<void> renameDeck(DeckId id, String name) async {
    await (_db.update(_db.decks)..where((deck) => deck.id.equals(id.value)))
        .write(DecksCompanion(name: Value(name), updatedAt: Value(_clock())));
  }

  /// Deletes the deck and, through the foreign key, every card in it.
  Future<void> deleteDeck(DeckId id) async {
    await (_db.delete(
      _db.decks,
    )..where((deck) => deck.id.equals(id.value))).go();
  }

  /// The number of cards in the deck.
  Future<int> countCards(DeckId deckId) async {
    final count = _db.cards.id.count();
    final query = _db.selectOnly(_db.cards)
      ..addColumns([count])
      ..where(_db.cards.deckId.equals(deckId.value));
    final row = await query.getSingle();
    return row.read(count) ?? 0;
  }

  /// The deck's cards, oldest first, re-emitted on each change.
  Stream<List<Card>> watchCards(DeckId deckId) {
    final query = _db.select(_db.cards)
      ..where((card) => card.deckId.equals(deckId.value))
      ..orderBy([(card) => OrderingTerm.asc(card.createdAt)]);
    return query.watch().map((rows) => rows.map(_toCard).toList());
  }

  /// Adds a manual card. A card in the same deck with an equal key blocks the
  /// save unless [allowDuplicate] is set.
  Future<SaveCardResult> addCard(
    DeckId deckId, {
    required List<Content> front,
    required List<Content> back,
    bool allowDuplicate = false,
  }) {
    final key = CardKey.fromFront(plainText(front));
    return _db.transaction(() async {
      if (!allowDuplicate) {
        final existing = await _findByKey(deckId, key);
        if (existing != null) {
          return DuplicateFront(existing);
        }
      }
      final now = _clock();
      final row = CardRow(
        id: _newId(),
        deckId: deckId.value,
        front: encodeContent(front),
        back: encodeContent(back),
        cardKey: key.value,
        source: CardSource.manual.name,
        createdAt: now,
        updatedAt: now,
      );
      await _db.into(_db.cards).insert(row);
      return CardSaved(_toCard(row));
    });
  }

  /// Replaces [card]'s front and back. Another card in the same deck with an
  /// equal key blocks the save unless [allowDuplicate] is set.
  Future<SaveCardResult> editCard(
    Card card, {
    required List<Content> front,
    required List<Content> back,
    bool allowDuplicate = false,
  }) {
    final key = CardKey.fromFront(plainText(front));
    return _db.transaction(() async {
      if (!allowDuplicate) {
        final existing = await _findByKey(card.deckId, key, except: card.id);
        if (existing != null) {
          return DuplicateFront(existing);
        }
      }
      final now = _clock();
      await (_db.update(
        _db.cards,
      )..where((row) => row.id.equals(card.id.value))).write(
        CardsCompanion(
          front: Value(encodeContent(front)),
          back: Value(encodeContent(back)),
          cardKey: Value(key.value),
          updatedAt: Value(now),
        ),
      );
      return CardSaved(
        Card(
          id: card.id,
          deckId: card.deckId,
          front: front,
          back: back,
          cardKey: key,
          source: card.source,
          createdAt: card.createdAt,
          updatedAt: now,
        ),
      );
    });
  }

  Future<void> deleteCard(CardId id) async {
    await (_db.delete(
      _db.cards,
    )..where((card) => card.id.equals(id.value))).go();
  }

  /// One lookup on the `(deck_id, card_key)` index.
  Future<Card?> _findByKey(DeckId deckId, CardKey key, {CardId? except}) async {
    final query = _db.select(_db.cards)
      ..where(
        (card) =>
            card.deckId.equals(deckId.value) &
            card.cardKey.equals(key.value) &
            (except == null
                ? const Constant(true)
                : card.id.equals(except.value).not()),
      )
      ..limit(1);
    final row = await query.getSingleOrNull();
    return row == null ? null : _toCard(row);
  }

  Deck _toDeck(DeckRow row) => Deck(
    id: DeckId(row.id),
    name: row.name,
    createdAt: row.createdAt,
    updatedAt: row.updatedAt,
  );

  Card _toCard(CardRow row) => Card(
    id: CardId(row.id),
    deckId: DeckId(row.deckId),
    front: decodeContent(row.front),
    back: decodeContent(row.back),
    cardKey: CardKey.stored(row.cardKey),
    source: CardSource.values.byName(row.source),
    createdAt: row.createdAt,
    updatedAt: row.updatedAt,
  );
}
