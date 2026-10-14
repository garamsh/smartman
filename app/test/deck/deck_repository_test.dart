import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smartman/deck/deck.dart';
import 'package:smartman/shared/database.dart';

List<Content> _text(String text) => [TextContent(text)];

DeckRepository _repository(AppDatabase db) {
  var nextId = 0;
  var tick = 0;
  return DeckRepository(
    db,
    clock: () => DateTime.utc(2026, 1, 1).add(Duration(seconds: tick++)),
    newId: () => 'id-${nextId++}',
  );
}

Card _saved(SaveCardResult result) => switch (result) {
  CardSaved(:final card) => card,
  DuplicateFront() => fail('expected the card to be saved, got $result'),
};

void main() {
  group('with an in-memory database', () {
    late AppDatabase db;
    late DeckRepository repository;

    setUp(() {
      db = AppDatabase(NativeDatabase.memory());
      repository = _repository(db);
    });

    tearDown(() => db.close());

    Future<List<Card>> cardsOf(DeckId deckId) =>
        repository.watchCards(deckId).first;

    group('duplicate rule', () {
      test(
        'refuses an equal key in the same deck and allows it in another deck',
        () async {
          final french = await repository.createDeck('French');
          final spanish = await repository.createDeck('Spanish');
          final first = _saved(
            await repository.addCard(
              french.id,
              front: _text('Hola'),
              back: _text('hello'),
            ),
          );
          expect(await cardsOf(french.id), hasLength(1));

          final sameDeck = await repository.addCard(
            french.id,
            front: _text('  HOLA '),
            back: _text('hi'),
          );
          final otherDeck = await repository.addCard(
            spanish.id,
            front: _text('  HOLA '),
            back: _text('hi'),
          );

          expect(sameDeck, isA<DuplicateFront>());
          expect((sameDeck as DuplicateFront).existing.id, first.id);
          expect(await cardsOf(french.id), hasLength(1));
          expect(otherDeck, isA<CardSaved>());
          expect(await cardsOf(spanish.id), hasLength(1));
        },
      );

      test('add anyway stores the second card', () async {
        final deck = await repository.createDeck('French');
        await repository.addCard(
          deck.id,
          front: _text('chat'),
          back: _text('cat'),
        );
        expect(await cardsOf(deck.id), hasLength(1));

        final result = await repository.addCard(
          deck.id,
          front: _text('Chat'),
          back: _text('chat (talk)'),
          allowDuplicate: true,
        );

        expect(result, isA<CardSaved>());
        final cards = await cardsOf(deck.id);
        expect(cards.map((card) => card.back), [
          _text('cat'),
          _text('chat (talk)'),
        ]);
      });

      test('refuses an edit that collides with another card and allows one that keeps its own key', () async {
        final deck = await repository.createDeck('French');
        final chat = _saved(
          await repository.addCard(
            deck.id,
            front: _text('chat'),
            back: _text('cat'),
          ),
        );
        final chien = _saved(
          await repository.addCard(
            deck.id,
            front: _text('chien'),
            back: _text('dog'),
          ),
        );

        final collision = await repository.editCard(
          chien,
          front: _text('CHAT'),
          back: _text('dog'),
        );
        final ownKey = await repository.editCard(
          chien,
          front: _text('Chien'),
          back: _text('dog!'),
        );

        expect(collision, isA<DuplicateFront>());
        expect((collision as DuplicateFront).existing.id, chat.id);
        expect(ownKey, isA<CardSaved>());
        final cards = await cardsOf(deck.id);
        expect(cards.map((card) => card.front), [
          _text('chat'),
          _text('Chien'),
        ]);
      });
    });

    test('editing a card stores the new front, back, and key', () async {
      final deck = await repository.createDeck('French');
      final card = _saved(
        await repository.addCard(deck.id, front: _text('a'), back: _text('b')),
      );

      await repository.editCard(
        card,
        front: _text('Pomme'),
        back: _text('apple'),
      );

      final stored = (await cardsOf(deck.id)).single;
      expect(stored.front, _text('Pomme'));
      expect(stored.back, _text('apple'));
      expect(stored.cardKey, CardKey.fromFront('pomme'));
      expect(stored.source, CardSource.manual);
    });

    test('deleting a card removes only that card', () async {
      final deck = await repository.createDeck('French');
      final kept = _saved(
        await repository.addCard(deck.id, front: _text('a'), back: _text('1')),
      );
      final removed = _saved(
        await repository.addCard(deck.id, front: _text('b'), back: _text('2')),
      );

      await repository.deleteCard(removed.id);

      expect((await cardsOf(deck.id)).map((card) => card.id), [kept.id]);
    });

    test('renaming a deck changes its name', () async {
      final deck = await repository.createDeck('Frnech');

      await repository.renameDeck(deck.id, 'French');

      expect((await repository.watchDecks().first).single.name, 'French');
    });

    test('deleting a deck deletes its cards and leaves other decks', () async {
      final french = await repository.createDeck('French');
      final spanish = await repository.createDeck('Spanish');
      await repository.addCard(french.id, front: _text('a'), back: _text('1'));
      await repository.addCard(spanish.id, front: _text('b'), back: _text('2'));
      expect(await repository.countCards(french.id), 1);

      await repository.deleteDeck(french.id);

      final remaining = await db.select(db.cards).get();
      expect(remaining.map((row) => row.deckId), [spanish.id.value]);
      expect((await repository.watchDecks().first).map((deck) => deck.id), [
        spanish.id,
      ]);
    });

    test('reads a stored block of an unknown type without failing', () async {
      final deck = await repository.createDeck('French');
      await db
          .into(db.cards)
          .insert(
            CardsCompanion.insert(
              id: 'stored',
              deckId: deck.id.value,
              front:
                  '[{"type":"text","payload":{"text":"chat"}},'
                  '{"type":"audio","payload":{"path":"chat.m4a"}}]',
              back: '[{"type":"text","payload":{"text":"cat"}}]',
              cardKey: 'chat',
              source: 'manual',
              createdAt: DateTime.utc(2026),
              updatedAt: DateTime.utc(2026),
            ),
          );

      final card = (await cardsOf(deck.id)).single;

      expect(card.front.first, const TextContent('chat'));
      expect(card.front.last, isA<UnsupportedContent>());
    });

    test('a write the database refuses is a storage failure, and a valid one is not', () async {
      final deck = await repository.createDeck('French');

      final valid = repository.addCard(
        deck.id,
        front: _text('chat'),
        back: _text('cat'),
      );
      final orphan = repository.addCard(
        const DeckId('missing'),
        front: _text('chien'),
        back: _text('dog'),
      );

      await expectLater(valid, completion(isA<CardSaved>()));
      await expectLater(orphan, throwsA(isA<StorageFailure>()));
    });

    test(
      'a stored card that cannot be decoded is reported as unreadable',
      () async {
        final deck = await repository.createDeck('French');
        await db
            .into(db.cards)
            .insert(
              CardsCompanion.insert(
                id: 'broken',
                deckId: deck.id.value,
                front: 'not json',
                back: '[]',
                cardKey: 'broken',
                source: 'manual',
                createdAt: DateTime.utc(2026),
                updatedAt: DateTime.utc(2026),
              ),
            );

        await expectLater(
          cardsOf(deck.id),
          throwsA(
            isA<UnreadableCard>().having(
              (failure) => failure.cardId,
              'cardId',
              const CardId('broken'),
            ),
          ),
        );
      },
    );

    test('the cards table indexes deck id and card key', () async {
      final indexes = await db
          .customSelect(
            "SELECT sql FROM sqlite_master WHERE type = 'index' AND tbl_name = 'cards'",
          )
          .map((row) => row.read<String?>('sql'))
          .get();

      expect(indexes, contains(contains('(deck_id, card_key)')));
    });
  });

  test(
    'data written before closing the database is read after reopening',
    () async {
      final dir = await Directory.systemTemp.createTemp('smartman_db');
      addTearDown(() => dir.delete(recursive: true));
      final file = File('${dir.path}/smartman.sqlite');

      final before = AppDatabase(NativeDatabase(file));
      final writer = _repository(before);
      final deck = await writer.createDeck('French');
      await writer.addCard(deck.id, front: _text('chat'), back: _text('cat'));
      await before.close();

      final after = AppDatabase(NativeDatabase(file));
      addTearDown(after.close);
      final reopened = _repository(after);

      expect((await reopened.watchDecks().first).single.name, 'French');
      final card = (await reopened.watchCards(deck.id).first).single;
      expect(card.front, _text('chat'));
      expect(card.back, _text('cat'));
    },
  );
}
