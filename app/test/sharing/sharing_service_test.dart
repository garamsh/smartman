import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smartman/account/account.dart';
import 'package:smartman/database/database.dart';
import 'package:smartman/deck/deck.dart';
import 'package:smartman/sharing/sharing.dart';

import 'fakes.dart';

final _published = DateTime.utc(2026, 10, 15, 9);

PublicDeckSummary publicDeck(
  String id, {
  String name = 'French',
  String owner = '00000000-0000-4000-8000-00000000000b',
  String ownerName = 'Bea',
  String? description,
  int cards = 0,
  int copies = 0,
  DateTime? publishedAt,
}) => PublicDeckSummary(
  id: DeckId(id),
  owner: UserId(owner),
  ownerName: DisplayName.tryParse(ownerName)!,
  name: name,
  description: description,
  cardCount: cards,
  copyCount: copies,
  publishedAt: publishedAt ?? _published,
);

PublicCard publicCard(String front, String back) =>
    PublicCard(front: [TextContent(front)], back: [TextContent(back)]);

void main() {
  late AppDatabase db;
  late DeckRepository decks;
  late FakeSharingServer server;
  late SharingService sharing;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    var ids = 0;
    var tick = 0;
    // Each write a second later, so cards list in the order they were written.
    decks = DeckRepository(
      db,
      clock: () =>
          DateTime.utc(2026, 10, 15, 10).add(Duration(seconds: tick++)),
      newId: () => 'id${ids++}',
    );
    server = FakeSharingServer();
    sharing = SharingService(
      server: server,
      decks: decks,
      reachability: FakeReachability(),
      clock: () => _published,
    );
  });

  tearDown(() => db.close());

  group('display name', () {
    test('takes 2 to 20 characters, trimmed', () {
      expect(DisplayName.tryParse('  Bea ')?.value, 'Bea');
      expect(DisplayName.tryParse('가나')?.value, '가나');
      expect(DisplayName.tryParse('a' * 20)?.value, 'a' * 20);
    });

    test('refuses fewer than 2 or more than 20 characters', () {
      expect(DisplayName.tryParse(' B '), isNull);
      expect(DisplayName.tryParse(''), isNull);
      expect(DisplayName.tryParse('a' * 21), isNull);
      // Characters, not UTF-16 units: 20 emoji are 40 units.
      expect(DisplayName.tryParse('😀' * 20), isNotNull);
    });
  });

  group('publishing', () {
    test(
      'a publish writes the server, then the device, with the description',
      () async {
        final deck = await decks.createDeck('French');
        server.name = DisplayName.tryParse('Ada');

        await sharing.makePublic(deck.id, description: 'Verbs');

        expect(server.writes, hasLength(1));
        expect(server.writes.single.deck.name, 'French');
        expect(server.writes.single.description, 'Verbs');
        final stored = await decks.getDeck(deck.id);
        expect(stored.visibility, isA<PublicDeck>());
        expect(
          (stored.visibility as PublicDeck).publishedAt.isAtSameMomentAs(
            _published,
          ),
          isTrue,
        );
        expect(stored.description, 'Verbs');
      },
    );

    test('a first publish sets the display name before the deck', () async {
      final deck = await decks.createDeck('French');
      expect(server.name, isNull);

      await sharing.makePublic(deck.id, name: DisplayName.tryParse('Ada'));

      expect(server.name?.value, 'Ada');
      expect(server.writes.single.visibility, isA<PublicDeck>());
    });

    test(
      'a publish the server refuses leaves the deck private on the device',
      () async {
        final deck = await decks.createDeck('French');
        server.failure = SharingOffline(Exception('no network'));

        await expectLater(
          sharing.makePublic(deck.id),
          throwsA(isA<SharingOffline>()),
        );

        expect((await decks.getDeck(deck.id)).visibility, isA<PrivateDeck>());
        // Control: the same publish goes through once the server answers.
        server.failure = null;
        await sharing.makePublic(deck.id);
        expect((await decks.getDeck(deck.id)).visibility, isA<PublicDeck>());
      },
    );

    test(
      'unpublishing makes the deck private and keeps its description',
      () async {
        final deck = await decks.createDeck('French');
        await sharing.makePublic(deck.id, description: 'Verbs');

        await sharing.makePrivate(deck.id);

        expect(server.writes.last.visibility, isA<PrivateDeck>());
        final stored = await decks.getDeck(deck.id);
        expect(stored.visibility, isA<PrivateDeck>());
        expect(stored.description, 'Verbs');
        final row = await db.select(db.decks).getSingle();
        expect(
          [row.visibility, row.publishedAt, row.dirty],
          ['private', null, true],
        );
      },
    );
  });

  group('copying', () {
    final source = publicDeck('public', name: 'Spanish', cards: 3);

    setUp(() {
      server.decks = [source];
      server.cards = {
        source.id: [
          publicCard('perro', 'dog'),
          publicCard('gato', 'cat'),
          publicCard('Perro', 'hound'),
        ],
      };
    });

    Future<List<(String, String, CardSource, String?)>> cardsOf(
      DeckId deck,
    ) async => [
      for (final card in await decks.listCards(deck))
        (
          plainText(card.front),
          plainText(card.back),
          card.source,
          card.originDeckId?.value,
        ),
    ];

    test(
      'as a new deck takes every card, named after the source, as shared cards',
      () async {
        final imported = await sharing.copy(source, const CopyIntoNewDeck());

        expect(imported.deck.name, 'Spanish');
        expect(imported.added, 3);
        expect(await cardsOf(imported.deck.id), [
          ('perro', 'dog', CardSource.copy, 'public'),
          ('gato', 'cat', CardSource.copy, 'public'),
          ('Perro', 'hound', CardSource.copy, 'public'),
        ]);
        expect(server.imports, [source.id]);
      },
    );

    test("keeps a table card's blocks as the source stores them, beside a text "
        'card', () async {
      const front = [
        TextContent('Capitals'),
        TableContent(
          columns: ['Capital', 'Country'],
          rows: [
            ['Paris', 'France'],
          ],
          blanks: [(row: 0, column: 0)],
        ),
      ];
      server.cards = {
        source.id: [
          const PublicCard(
            front: front,
            back: [TextContent('Capital | Country\nParis | France')],
          ),
          publicCard('perro', 'dog'),
        ],
      };

      final imported = await sharing.copy(source, const CopyIntoNewDeck());

      final [table, text] = await decks.listCards(imported.deck.id);
      expect(table.front, front);
      // Control: a text card is copied as its text.
      expect(text.front, [const TextContent('perro')]);
    });

    Future<Deck> mine() async {
      final deck = await decks.createDeck('Mine');
      await decks.addCard(
        deck.id,
        front: [const TextContent('perro')],
        back: [const TextContent('dog')],
      );
      return deck;
    }

    test('into an existing deck skips duplicates by default', () async {
      final deck = await mine();

      final imported = await sharing.copy(
        source,
        CopyIntoDeck(deck.id, DuplicateChoice.skip),
      );

      expect([imported.added, imported.merged], [1, 0]);
      expect(await cardsOf(deck.id), [
        ('perro', 'dog', CardSource.manual, null),
        ('gato', 'cat', CardSource.copy, 'public'),
      ]);
    });

    test('into an existing deck merges backs when asked', () async {
      final deck = await mine();

      final imported = await sharing.copy(
        source,
        CopyIntoDeck(deck.id, DuplicateChoice.mergeBack),
      );

      expect([imported.added, imported.merged], [1, 1]);
      expect(await cardsOf(deck.id), [
        ('perro', 'dog\nhound', CardSource.manual, null),
        ('gato', 'cat', CardSource.copy, 'public'),
      ]);
    });

    test(
      'into an existing deck adds duplicates as new cards when asked',
      () async {
        final deck = await mine();

        final imported = await sharing.copy(
          source,
          CopyIntoDeck(deck.id, DuplicateChoice.addNew),
        );

        expect([imported.added, imported.merged], [3, 0]);
        expect(await cardsOf(deck.id), hasLength(4));
      },
    );

    test('a deck no longer public is refused and nothing is written', () async {
      server.decks = [];

      await expectLater(
        sharing.copy(source, const CopyIntoNewDeck()),
        throwsA(isA<DeckNoLongerPublic>()),
      );

      expect(await db.select(db.decks).get(), isEmpty);
      expect(server.imports, isEmpty);
    });
  });
}
