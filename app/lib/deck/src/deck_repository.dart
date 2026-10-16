import 'dart:async';

import 'package:drift/drift.dart';

import '../../database/database.dart';
import 'card_import.dart';
import 'card_key.dart';
import 'content.dart';
import 'failure.dart';
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
///
/// Every database failure reaches the caller as [StorageFailure], and a card
/// whose stored content cannot be decoded as [UnreadableCard].
class DeckRepository {
  DeckRepository(this._db, {required this._clock, required this._newId});

  final AppDatabase _db;
  final DateTime Function() _clock;
  final String Function() _newId;

  /// Every deck, ordered by name, re-emitted on each change.
  Stream<List<Deck>> watchDecks() {
    final query = _db.select(_db.decks)
      ..where((deck) => deck.deletedAt.isNull())
      ..orderBy([(deck) => OrderingTerm.asc(deck.name)]);
    return _guardStream(
      query.watch().map((rows) => rows.map(_toDeck).toList()),
    );
  }

  Future<Deck> createDeck(String name) => _guard(() async {
    final now = _clock();
    final row = DeckRow(
      id: _newId(),
      name: name,
      visibility: _visibilityName(const PrivateDeck()),
      createdAt: now,
      updatedAt: now,
      dirty: true,
    );
    await _db.into(_db.decks).insert(row);
    return _toDeck(row);
  });

  Future<void> renameDeck(DeckId id, String name) => _guard(() async {
    await (_db.update(
      _db.decks,
    )..where((deck) => deck.id.equals(id.value))).write(
      DecksCompanion(
        name: Value(name),
        updatedAt: Value(_clock()),
        dirty: const Value(true),
      ),
    );
  });

  /// Publishes the deck as [visibility] says, with [description] when it is
  /// public; a private deck keeps the description it had, for the next
  /// publish. Refused with [DeckDeleted] once the deck is deleted.
  Future<Deck> setVisibility(
    DeckId id,
    DeckVisibility visibility, {
    String? description,
  }) => _guard(
    () => _db.transaction(() async {
      await getDeck(id);
      await (_db.update(
        _db.decks,
      )..where((deck) => deck.id.equals(id.value))).write(
        DecksCompanion(
          visibility: Value(_visibilityName(visibility)),
          publishedAt: Value(switch (visibility) {
            PublicDeck(:final publishedAt) => publishedAt,
            PrivateDeck() => null,
          }),
          description: switch (visibility) {
            PublicDeck() => Value(description),
            PrivateDeck() => const Value.absent(),
          },
          updatedAt: Value(_clock()),
          dirty: const Value(true),
        ),
      );
      return getDeck(id);
    }),
  );

  /// The deck, re-emitted on each change; null once it is deleted.
  Stream<Deck?> watchDeck(DeckId id) {
    final query = _db.select(_db.decks)
      ..where((deck) => deck.id.equals(id.value) & deck.deletedAt.isNull());
    return _guardStream(
      query.watchSingleOrNull().map((row) => row == null ? null : _toDeck(row)),
    );
  }

  /// Deletes the deck and every card in it, as tombstones sync pushes.
  Future<void> deleteDeck(DeckId id) => _guard(
    () => _db.transaction(() async {
      final now = _clock();
      await (_db.update(
        _db.decks,
      )..where((deck) => deck.id.equals(id.value))).write(_deckTombstone(now));
      await (_db.update(_db.cards)..where(
            (card) => card.deckId.equals(id.value) & card.deletedAt.isNull(),
          ))
          .write(_cardTombstone(now));
    }),
  );

  /// The number of cards in the deck.
  Future<int> countCards(DeckId deckId) => _guard(() async {
    final count = _db.cards.id.count();
    final query = _db.selectOnly(_db.cards)
      ..addColumns([count])
      ..where(
        _db.cards.deckId.equals(deckId.value) & _db.cards.deletedAt.isNull(),
      );
    final row = await query.getSingle();
    return row.read(count) ?? 0;
  });

  /// How many cards each deck holds, re-emitted on each change. A deck with
  /// no card is absent.
  Stream<Map<DeckId, int>> watchCardCounts() {
    final count = _db.cards.id.count();
    final query = _db.selectOnly(_db.cards)
      ..addColumns([_db.cards.deckId, count])
      ..where(_db.cards.deletedAt.isNull())
      ..groupBy([_db.cards.deckId]);
    return _guardStream(
      query.watch().map(
        (rows) => {
          for (final row in rows)
            // deck_id is NOT NULL, so every grouped row carries one.
            if (row.read(_db.cards.deckId) case final deck?)
              DeckId(deck): row.read(count) ?? 0,
        },
      ),
    );
  }

  /// The deck's cards, oldest first, re-emitted on each change.
  Stream<List<Card>> watchCards(DeckId deckId) {
    final query = _db.select(_db.cards)
      ..where(
        (card) => card.deckId.equals(deckId.value) & card.deletedAt.isNull(),
      )
      ..orderBy([(card) => OrderingTerm.asc(card.createdAt)]);
    return _guardStream(
      query.watch().map((rows) => rows.map(_toCard).toList()),
    );
  }

  /// The deck's cards, oldest first.
  Future<List<Card>> listCards(DeckId deckId) => _guard(() async {
    final query = _db.select(_db.cards)
      ..where(
        (card) => card.deckId.equals(deckId.value) & card.deletedAt.isNull(),
      )
      ..orderBy([(card) => OrderingTerm.asc(card.createdAt)]);
    return (await query.get()).map(_toCard).toList();
  });

  /// Adds a manual card. A card in the same deck with an equal key blocks the
  /// save unless [allowDuplicate] is set.
  Future<SaveCardResult> addCard(
    DeckId deckId, {
    required List<Content> front,
    required List<Content> back,
    bool allowDuplicate = false,
  }) {
    final key = CardKey.fromFront(plainText(front));
    return _guard(
      () => _db.transaction(() async {
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
          dirty: true,
        );
        await _db.into(_db.cards).insert(row);
        return CardSaved(_toCard(row));
      }),
    );
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
    return _guard(
      () => _db.transaction(() async {
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
            dirty: const Value(true),
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
      }),
    );
  }

  /// Deletes the card as a tombstone sync pushes.
  Future<void> deleteCard(CardId id) => _guard(() async {
    await (_db.update(_db.cards)..where((card) => card.id.equals(id.value)))
        .write(_cardTombstone(_clock()));
  });

  /// Saves [cards] from [source] into [target] in one transaction, creating
  /// the deck first when the target is a new one. A card whose key collides
  /// with a card already in the deck, or with one saved earlier in [cards],
  /// does what its [ImportedCard.onDuplicate] says; no card is overwritten or
  /// deleted.
  Future<CardsImported> importCards(
    ImportTarget target,
    List<ImportedCard> cards, {
    ImportSource source = const FromPhoto(),
  }) => _guard(
    () => _db.transaction(() async {
      final deck = switch (target) {
        ImportIntoDeck(:final deck) => await getDeck(deck),
        ImportIntoNewDeck(:final name) => await createDeck(name),
      };
      var added = 0;
      var merged = 0;
      for (final card in cards) {
        final key = CardKey.fromFront(card.front);
        final existing = await _findByKey(deck.id, key);
        switch ((existing, card.onDuplicate)) {
          case (null, _) || (_, DuplicateChoice.addNew):
            final now = _clock();
            await _db
                .into(_db.cards)
                .insert(
                  CardRow(
                    id: _newId(),
                    deckId: deck.id.value,
                    front: encodeContent([TextContent(card.front)]),
                    back: encodeContent([TextContent(card.back)]),
                    cardKey: key.value,
                    source: switch (source) {
                      FromPhoto() => CardSource.import.name,
                      FromPublicDeck() => CardSource.shared.name,
                    },
                    originDeckId: switch (source) {
                      FromPhoto() => null,
                      FromPublicDeck(:final origin) => origin.value,
                    },
                    createdAt: now,
                    updatedAt: now,
                    dirty: true,
                  ),
                );
            added++;
          case (final existing?, DuplicateChoice.mergeBack):
            if (mergeBack(existing.back, card.back) case final back?) {
              await (_db.update(
                _db.cards,
              )..where((row) => row.id.equals(existing.id.value))).write(
                CardsCompanion(
                  back: Value(encodeContent(back)),
                  updatedAt: Value(_clock()),
                  dirty: const Value(true),
                ),
              );
              merged++;
            }
          case (_?, DuplicateChoice.skip):
            break;
        }
      }
      return CardsImported(deck: deck, added: added, merged: merged);
    }),
  );

  /// The deck, unless it was deleted; then [DeckDeleted].
  Future<Deck> getDeck(DeckId id) => _guard(() async {
    final row =
        await (_db.select(_db.decks)..where(
              (deck) => deck.id.equals(id.value) & deck.deletedAt.isNull(),
            ))
            .getSingleOrNull();
    if (row == null) throw DeckDeleted(id);
    return _toDeck(row);
  });

  static String _visibilityName(DeckVisibility visibility) =>
      switch (visibility) {
        PrivateDeck() => 'private',
        PublicDeck() => 'public',
      };

  static DecksCompanion _deckTombstone(DateTime at) => DecksCompanion(
    deletedAt: Value(at),
    updatedAt: Value(at),
    dirty: const Value(true),
  );

  static CardsCompanion _cardTombstone(DateTime at) => CardsCompanion(
    deletedAt: Value(at),
    updatedAt: Value(at),
    dirty: const Value(true),
  );

  /// One lookup on the `(deck_id, card_key)` index.
  Future<Card?> _findByKey(DeckId deckId, CardKey key, {CardId? except}) async {
    final query = _db.select(_db.cards)
      ..where(
        (card) =>
            card.deckId.equals(deckId.value) &
            card.cardKey.equals(key.value) &
            card.deletedAt.isNull() &
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
    // A public row always carries its publish time; the server checks it.
    visibility: switch ((row.visibility, row.publishedAt)) {
      ('public', final publishedAt?) => PublicDeck(publishedAt),
      _ => const PrivateDeck(),
    },
    description: row.description,
  );

  Card _toCard(CardRow row) {
    final id = CardId(row.id);
    try {
      return Card(
        id: id,
        deckId: DeckId(row.deckId),
        front: decodeContent(row.front),
        back: decodeContent(row.back),
        cardKey: CardKey.stored(row.cardKey),
        source: CardSource.values.byName(row.source),
        createdAt: row.createdAt,
        updatedAt: row.updatedAt,
        originDeckId: switch (row.originDeckId) {
          final origin? => DeckId(origin),
          null => null,
        },
      );
    } on FormatException catch (cause) {
      throw UnreadableCard(id, cause);
    }
  }

  /// Runs [operation], reporting a database exception as [StorageFailure].
  Future<T> _guard<T>(Future<T> Function() operation) async {
    try {
      return await operation();
    } on DeckFailure {
      rethrow;
    } on Exception catch (cause, stackTrace) {
      Error.throwWithStackTrace(StorageFailure(cause), stackTrace);
    }
  }

  /// [stream] with each database exception reported as [StorageFailure].
  Stream<T> _guardStream<T>(Stream<T> stream) => stream.transform(
    StreamTransformer.fromHandlers(
      handleError: (error, stackTrace, sink) => sink.addError(
        error is Exception && error is! DeckFailure
            ? StorageFailure(error)
            : error,
        stackTrace,
      ),
    ),
  );
}
