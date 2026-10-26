import 'dart:async';

import 'package:drift/drift.dart';

import '../../database/database.dart';
import '../../media/media.dart';
import 'add_cards.dart';
import 'card_key.dart';
import 'card_kind.dart';
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
  DeckRepository(
    this._db, {
    required this._clock,
    required this._newId,
    String Function()? newBlockId,
    this._media,
  }) : _newBlockId = newBlockId ?? _newId;

  final AppDatabase _db;

  /// Releases each image or sound a deck or card lets go, by a new one or
  /// its deletion; without it, as in a test that stores none, none is
  /// released.
  final MediaStore? _media;
  final DateTime Function() _clock;
  final String Function() _newId;

  /// Makes each block's id: [_newId] unless another is given, so a test can
  /// keep its card ids apart from its block ids.
  final String Function() _newBlockId;

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

  /// Stores [icon] and [color] as the deck's appearance.
  Future<void> setAppearance(DeckId id, DeckIcon icon, DeckColor color) =>
      _guard(() async {
        await (_db.update(
          _db.decks,
        )..where((deck) => deck.id.equals(id.value))).write(
          DecksCompanion(
            icon: Value(icon.key),
            color: Value(color.key),
            updatedAt: Value(_clock()),
            dirty: const Value(true),
          ),
        );
      });

  /// Stores [image] as the deck's image, or none when it is null, and
  /// releases the image it replaces unless another holds it.
  Future<void> setImage(DeckId id, MediaId? image) => _guard(
    () => _db.transaction(() async {
      final previous = await _imageOf(id);
      await (_db.update(
        _db.decks,
      )..where((deck) => deck.id.equals(id.value))).write(
        DecksCompanion(
          imageMediaId: Value(image?.value),
          updatedAt: Value(_clock()),
          dirty: const Value(true),
        ),
      );
      if (previous != null && previous != image) {
        await _releaseUnheld({previous});
      }
    }),
  );

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

  /// Deletes the deck and every card in it, as tombstones sync pushes, and
  /// releases its image and its cards' photos and sounds unless another
  /// holds them.
  Future<void> deleteDeck(DeckId id) => _guard(
    () => _db.transaction(() async {
      final now = _clock();
      final cards = _db.select(_db.cards)
        ..where(
          (card) => card.deckId.equals(id.value) & card.deletedAt.isNull(),
        );
      final images = {
        ?await _imageOf(id),
        for (final row in await cards.get()) ..._mediaOf(row),
      };
      await (_db.update(
        _db.decks,
      )..where((deck) => deck.id.equals(id.value))).write(_deckTombstone(now));
      await (_db.update(_db.cards)..where(
            (card) => card.deckId.equals(id.value) & card.deletedAt.isNull(),
          ))
          .write(_cardTombstone(now));
      await _releaseUnheld(images);
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

  /// Adds a manual card, recording [kind]'s template, or the one its front
  /// derives when [kind] is null. A card in the same deck with an equal key
  /// blocks the save unless [allowDuplicate] is set.
  Future<SaveCardResult> addCard(
    DeckId deckId, {
    required List<Content> front,
    required List<Content> back,
    CardKind? kind,
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
          front: encodeContent(_withIds(front, const [])),
          back: encodeContent(_withIds(back, const [])),
          cardKey: key.value,
          source: CardSource.manual.name,
          template: (kind ?? derivedKind(front)).template,
          templateVersion: cardTemplateVersion,
          createdAt: now,
          updatedAt: now,
          dirty: true,
        );
        await _db.into(_db.cards).insert(row);
        return CardSaved(_toCard(row));
      }),
    );
  }

  /// Replaces [card]'s front and back, recording [kind]'s template, or the
  /// card's own when [kind] is null. Another card in the same deck with an
  /// equal key blocks the save unless [allowDuplicate] is set. Content that
  /// cannot be read back is not stored: the save fails as [UnreadableCard].
  Future<SaveCardResult> editCard(
    Card card, {
    required List<Content> front,
    required List<Content> back,
    CardKind? kind,
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
        final stored = await (_db.select(
          _db.cards,
        )..where((row) => row.id.equals(card.id.value))).getSingle();
        final now = _clock();
        final (template, templateVersion) = _templateFor(card, kind);
        await (_db.update(
          _db.cards,
        )..where((row) => row.id.equals(card.id.value))).write(
          CardsCompanion(
            front: Value(encodeContent(_withIds(front, card.front))),
            back: Value(encodeContent(_withIds(back, card.back))),
            cardKey: Value(key.value),
            template: Value(template),
            templateVersion: Value(templateVersion),
            updatedAt: Value(now),
            dirty: const Value(true),
          ),
        );
        // Read back as any card is read, so content the decoder refuses
        // throws here and the write rolls back, as an add's does.
        final row = await (_db.select(
          _db.cards,
        )..where((row) => row.id.equals(card.id.value))).getSingle();
        await _releaseUnheld(_mediaOf(stored));
        return CardSaved(_toCard(row));
      }),
    );
  }

  /// Deletes the card as a tombstone sync pushes, and releases its photos and
  /// sounds unless another holds them.
  Future<void> deleteCard(CardId id) => _guard(
    () => _db.transaction(() async {
      final cards = _db.select(_db.cards)
        ..where((card) => card.id.equals(id.value));
      final images = {for (final row in await cards.get()) ..._mediaOf(row)};
      await (_db.update(_db.cards)..where((card) => card.id.equals(id.value)))
          .write(_cardTombstone(_clock()));
      await _releaseUnheld(images);
    }),
  );

  /// Saves [cards] from [source] into [target] in one transaction, creating
  /// the deck first when the target is a new one. A card whose key collides
  /// with a card already in the deck, or with one saved earlier in [cards],
  /// does what its [IncomingCard.onDuplicate] says; no card is overwritten or
  /// deleted.
  Future<CardsAdded> addCards(
    AddTarget target,
    List<IncomingCard> cards, {
    AddSource source = const FromPhoto(),
  }) => _guard(
    () => _db.transaction(() async {
      final deck = switch (target) {
        AddToDeck(:final deck) => await getDeck(deck),
        AddToNewDeck(:final name) => await createDeck(name),
      };
      var added = 0;
      var merged = 0;
      for (final card in cards) {
        final key = CardKey.fromFront(plainText(card.front));
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
                    front: encodeContent(_withIds(card.front, const [])),
                    back: encodeContent(_withIds(card.back, const [])),
                    cardKey: key.value,
                    template: derivedKind(card.front).template,
                    templateVersion: cardTemplateVersion,
                    source: switch (source) {
                      FromPhoto() => CardSource.import.name,
                      FromCopy() => CardSource.copy.name,
                    },
                    originDeckId: switch (source) {
                      FromPhoto() => null,
                      FromCopy(:final origin) => origin.value,
                    },
                    createdAt: now,
                    updatedAt: now,
                    dirty: true,
                  ),
                );
            added++;
          case (final existing?, DuplicateChoice.mergeBack):
            if (mergeBack(existing.back, plainText(card.back))
                case final back?) {
              await (_db.update(
                _db.cards,
              )..where((row) => row.id.equals(existing.id.value))).write(
                CardsCompanion(
                  back: Value(encodeContent(_withIds(back, existing.back))),
                  template: Value(_templateFor(existing, null).$1),
                  templateVersion: Value(_templateFor(existing, null).$2),
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
      return CardsAdded(deck: deck, added: added, merged: merged);
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

  /// [blocks] as written: each keeps its id, or takes the id of the next
  /// block of its kind in [previous] not yet taken, or a new one, so a block
  /// keeps its id across edits and every block has one once written
  /// (ADR 0106). A block this build cannot read is kept as it is.
  List<Content> _withIds(List<Content> blocks, List<Content> previous) {
    final unused = [
      for (final block in previous)
        if (block.id != null && block is! UnsupportedContent) block,
    ];
    final taken = {for (final block in blocks) ?block.id};
    return [
      for (final block in blocks)
        switch (block) {
          UnsupportedContent() || Content(id: _?) => block,
          _ => withBlockId(block, switch (unused.indexWhere(
            (old) =>
                old.runtimeType == block.runtimeType && !taken.contains(old.id),
          )) {
            -1 => _newBlockId(),
            final index => unused.removeAt(index).id!,
          }),
        },
    ];
  }

  /// The template and version a write of [card] records: [kind]'s when the
  /// editor names one; otherwise the card's own, kept as it is, a template
  /// this build does not know included; or, when it records none yet, the
  /// one its front derives, filled in on this write (ADR 0106).
  static (String, int?) _templateFor(Card card, CardKind? kind) =>
      switch ((kind, card.template)) {
        (final kind?, _) => (kind.template, cardTemplateVersion),
        (null, final template?) => (template, card.templateVersion),
        (null, null) => (derivedKind(card.front).template, cardTemplateVersion),
      };

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

  /// The photos and sounds [row]'s sides hold (ADR 0109, ADR 0112). A side
  /// this build cannot decode names no file it can find, so it gives none.
  static Set<MediaId> _mediaOf(CardRow row) => {
    for (final side in [row.front, row.back]) ..._mediaOfSide(side),
  };

  static Set<MediaId> _mediaOfSide(String side) {
    try {
      return mediaOf(decodeContent(side));
    } on FormatException {
      return const {};
    }
  }

  /// Releases each of [images] that no live deck or card still holds, as a
  /// copied card or deck keeps the media id of the one it was copied from.
  /// Called after the write, inside its transaction, so the rows read are
  /// the ones the write leaves.
  Future<void> _releaseUnheld(Set<MediaId> images) async {
    final media = _media;
    if (media == null) return;
    for (final image in images) {
      if (!await _isHeld(image)) await media.release(image);
    }
  }

  Future<bool> _isHeld(MediaId image) async {
    final deck = _db.selectOnly(_db.decks)
      ..addColumns([_db.decks.id])
      ..where(
        _db.decks.imageMediaId.equals(image.value) &
            _db.decks.deletedAt.isNull(),
      )
      ..limit(1);
    if (await deck.getSingleOrNull() != null) return true;
    // The pattern narrows the scan to rows naming the id; decoding decides.
    // A side this build cannot decode, but which names the id, holds it.
    final pattern = '%${image.value}%';
    final cards = _db.select(_db.cards)
      ..where(
        (card) =>
            card.deletedAt.isNull() &
            (card.front.like(pattern) | card.back.like(pattern)),
      );
    for (final row in await cards.get()) {
      for (final side in [row.front, row.back]) {
        if (!side.contains(image.value)) continue;
        try {
          if (mediaOf(decodeContent(side)).contains(image)) return true;
        } on FormatException {
          return true;
        }
      }
    }
    return false;
  }

  /// The image of deck [id]; null when it has none or is not stored.
  Future<MediaId?> _imageOf(DeckId id) async {
    final query = _db.selectOnly(_db.decks)
      ..addColumns([_db.decks.imageMediaId])
      ..where(_db.decks.id.equals(id.value));
    final image = (await query.getSingleOrNull())?.read(_db.decks.imageMediaId);
    return image == null ? null : MediaId(image);
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
    icon: DeckIcon.fromKey(row.icon),
    color: DeckColor.fromKey(row.color),
    image: switch (row.imageMediaId) {
      final image? => MediaId(image),
      null => null,
    },
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
        template: row.template,
        templateVersion: row.templateVersion,
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
