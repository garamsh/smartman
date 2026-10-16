import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';
import 'package:smartman/account/account.dart';
import 'package:smartman/database/database.dart';
import 'package:smartman/deck/deck.dart';
import 'package:smartman/study/study.dart';

import 'device.dart';
import 'fake_sync_server.dart';

const _ada = UserId('00000000-0000-4000-8000-00000000000a');
const _grace = UserId('00000000-0000-4000-8000-00000000000b');

List<Content> _text(String text) => [TextContent(text)];

void main() {
  late Scheduler scheduler;
  late FakeSyncServer server;
  late Device a;
  late Device b;

  setUpAll(() async => scheduler = await Scheduler.load());

  setUp(() {
    server = FakeSyncServer(_ada);
    a = Device('a', server, scheduler);
    b = Device('b', server, scheduler);
  });

  tearDown(() async {
    await a.close();
    await b.close();
  });

  Future<Card> addCard(Device device, Deck deck, String front) async {
    final saved = await device.deck.addCard(
      deck.id,
      front: _text(front),
      back: _text('$front back'),
      allowDuplicate: true,
    );
    return (saved as CardSaved).card;
  }

  group('push', () {
    test('sends every unsynced row and marks it synced', () async {
      final deck = await a.deck.createDeck('French');
      await addCard(a, deck, 'chat');
      expect(await a.store.hasUnsynced(), isTrue);

      await a.sync(_ada);

      expect(server.decks.keys, [deck.id.value]);
      expect(server.cards, hasLength(1));
      expect(await a.store.hasUnsynced(), isFalse);
    });

    test('a row edited while its push is under way stays unsynced', () async {
      final deck = await a.deck.createDeck('French');
      server.beforePush = (table) async {
        if (table != 'decks') return;
        a.now = a.now.add(const Duration(seconds: 1));
        await a.deck.renameDeck(deck.id, 'Français');
      };

      await a.sync(_ada);

      expect(server.decks[deck.id.value]!.row.name, 'French');
      expect(await a.store.hasUnsynced(), isTrue);
      // Control: the next run pushes the edit and leaves nothing unsynced.
      server.beforePush = null;
      await a.sync(_ada);
      expect(server.decks[deck.id.value]!.row.name, 'Français');
      expect(await a.store.hasUnsynced(), isFalse);
    });
  });

  group('pull', () {
    test(
      'brings rows above the cursor page by page, and moves the cursor',
      () async {
        final paged = Device('paged', server, scheduler, pageSize: 2);
        addTearDown(paged.close);
        final deck = await a.deck.createDeck('French');
        for (final front in ['un', 'deux', 'trois', 'quatre', 'cinq']) {
          a.now = a.now.add(const Duration(seconds: 1));
          await addCard(a, deck, front);
        }
        await a.sync(_ada);

        await paged.sync(_ada);

        final cards = await paged.deck.listCards(deck.id);
        expect(cards.map((card) => plainText(card.front)), [
          'un',
          'deux',
          'trois',
          'quatre',
          'cinq',
        ]);
        final last = server.cards.values
            .map((stored) => stored.revision)
            .reduce((x, y) => x > y ? x : y);
        expect((await paged.store.cursors()).cardsRevision, last);
        // Control: a pull from the moved cursor asks for nothing already seen.
        server.requests.clear();
        await paged.sync(_ada);
        expect(server.requests.where((r) => r == 'pullCards'), hasLength(1));
      },
    );

    test('stops a page at a row whose parent has not arrived', () async {
      final deck = await a.deck.createDeck('French');
      await addCard(a, deck, 'chat');
      await a.sync(_ada);
      await b.store.claim(_ada);
      final card = server.cards.values.single;

      final stopped = await b.store.applyCards([
        (row: card.row, revision: card.revision),
      ]);

      expect(stopped.complete, isFalse);
      expect(await b.db.select(b.db.cards).get(), isEmpty);
      expect((await b.store.cursors()).cardsRevision, 0);
      // Control: once the deck is on the device, the same page applies.
      final stored = server.decks.values.single;
      await b.store.applyDecks([(row: stored.row, revision: stored.revision)]);
      final applied = await b.store.applyCards([
        (row: card.row, revision: card.revision),
      ]);
      expect(applied.complete, isTrue);
      expect(await b.db.select(b.db.cards).get(), hasLength(1));
      expect((await b.store.cursors()).cardsRevision, card.revision);
    });

    test('a pulled row that loses its merge is pushed back', () async {
      final deck = await a.deck.createDeck('French');
      await a.sync(_ada);
      await b.sync(_ada);
      // B's later rename reaches the server first; A's earlier one overwrites it.
      b.now = a.now.add(const Duration(minutes: 2));
      await b.deck.renameDeck(deck.id, 'Later');
      await b.sync(_ada);
      a.now = a.now.add(const Duration(minutes: 1));
      await a.deck.renameDeck(deck.id, 'Earlier');
      await a.store.claim(_ada);
      await server.pushDecks(_ada, await a.store.unsyncedDecks());

      await b.sync(_ada);

      expect(await b.deckNames(), ['Later']);
      expect(server.decks[deck.id.value]!.row.name, 'Later');
    });
  });

  group('conflicts', () {
    Future<Deck> shared() async {
      final deck = await a.deck.createDeck('French');
      await a.sync(_ada);
      await b.sync(_ada);
      return deck;
    }

    test('an edit conflict keeps the later edit on both devices', () async {
      final deck = await shared();
      a.now = a.now.add(const Duration(minutes: 1));
      b.now = b.now.add(const Duration(minutes: 2));
      await a.deck.renameDeck(deck.id, 'Earlier');
      await b.deck.renameDeck(deck.id, 'Later');

      await b.sync(_ada);
      await a.sync(_ada);

      expect(await a.deckNames(), ['Later']);
      expect(await b.deckNames(), ['Later']);
    });

    test('the same edits with A\'s later keep A\'s', () async {
      final deck = await shared();
      a.now = a.now.add(const Duration(minutes: 2));
      b.now = b.now.add(const Duration(minutes: 1));
      await a.deck.renameDeck(deck.id, 'Later');
      await b.deck.renameDeck(deck.id, 'Earlier');

      await b.sync(_ada);
      await a.sync(_ada);
      await b.sync(_ada);

      expect(await a.deckNames(), ['Later']);
      expect(await b.deckNames(), ['Later']);
    });

    test('a delete beats a later concurrent edit', () async {
      final deck = await shared();
      a.now = a.now.add(const Duration(minutes: 1));
      b.now = b.now.add(const Duration(minutes: 2));
      await a.deck.deleteDeck(deck.id);
      await b.deck.renameDeck(deck.id, 'Edited after');

      await a.sync(_ada);
      await b.sync(_ada);
      await a.sync(_ada);

      expect(await a.deckNames(), isEmpty);
      expect(await b.deckNames(), isEmpty);
      expect(server.decks[deck.id.value]!.row.deletedAt, isNotNull);
    });

    test(
      'a review pulled for a card recomputes its state from every review',
      () async {
        final deck = await shared();
        final card = await addCard(a, deck, 'chat');
        await a.sync(_ada);
        await b.sync(_ada);
        a.now = a.now.add(const Duration(days: 1));
        b.now = b.now.add(const Duration(days: 2));
        await a.answer(card.id, 'good', fuzz: 0.2);
        await b.answer(card.id, 'again', fuzz: 0.7);
        final aBefore = await a.stateOf(card.id);

        await a.sync(_ada);
        await b.sync(_ada);
        await a.sync(_ada);

        final union = (await a.foldOf(card.id))!;
        expect(await a.db.select(a.db.reviews).get(), hasLength(2));
        expect(await b.db.select(b.db.reviews).get(), hasLength(2));
        for (final device in [a, b]) {
          final state = (await device.stateOf(card.id))!;
          expect(
            [
              state.stability,
              state.difficulty,
              state.due.millisecondsSinceEpoch,
            ],
            [
              union.stability,
              union.difficulty,
              union.due.millisecondsSinceEpoch,
            ],
            reason: device.name,
          );
        }
        // Control: A's own state before the pull was not already the union's.
        expect(aBefore!.stability, isNot(union.stability));
      },
    );

    test(
      'a pull that brings no review leaves a card state as it was',
      () async {
        final deck = await shared();
        final card = await addCard(a, deck, 'chat');
        await a.answer(card.id, 'good');
        await a.sync(_ada);
        await b.sync(_ada);
        // A state the fold would not give, written as synced.
        await (b.db.update(b.db.cardStates)).write(
          const CardStatesCompanion(stability: Value(99), dirty: Value(false)),
        );

        await a.deck.renameDeck(deck.id, 'Renamed');
        await a.sync(_ada);
        await b.sync(_ada);

        expect((await b.stateOf(card.id))!.stability, 99);
        // Control: a pulled review does replace it with the fold.
        a.now = a.now.add(const Duration(days: 1));
        await a.answer(card.id, 'good');
        await a.sync(_ada);
        await b.sync(_ada);
        expect(
          (await b.stateOf(card.id))!.stability,
          (await b.foldOf(card.id))!.stability,
        );
      },
    );

    test('equal-key cards from both devices both survive', () async {
      final deck = await shared();
      await addCard(a, deck, 'chat');
      await addCard(b, deck, 'Chat');

      await a.sync(_ada);
      await b.sync(_ada);
      await a.sync(_ada);

      for (final device in [a, b]) {
        final cards = await device.deck.listCards(deck.id);
        expect(cards, hasLength(2), reason: device.name);
        expect(cards.map((card) => card.cardKey.value).toSet(), {'chat'});
      }
    });
  });

  group('ownership', () {
    test(
      'rows from before any sign-in are pushed as the first account\'s',
      () async {
        await a.deck.createDeck('Before sign-in');
        expect(await a.store.owner(), isNull);

        await a.sync(_ada);

        expect(await a.store.owner(), _ada);
        expect(server.decks.values.single.owner, _ada);
        expect(server.decks.values.single.row.name, 'Before sign-in');
      },
    );

    test('a database another account owns is cleared, never pushed', () async {
      await a.deck.createDeck('Ada\'s');
      await a.sync(_ada);
      server.decks.clear();
      await a.deck.createDeck('Ada\'s unsynced');
      server.account = _grace;

      await a.sync(_grace);

      expect(server.decks, isEmpty);
      expect(await a.deckNames(), isEmpty);
      expect(await a.store.owner(), _grace);
      // Control: the same database, synced by its owner, pushes its rows.
      final other = Device('other', server, scheduler);
      addTearDown(other.close);
      await other.deck.createDeck('Grace\'s');
      await other.sync(_grace);
      await a.sync(_grace);
      expect(await a.deckNames(), ['Grace\'s']);
    });
  });
}
