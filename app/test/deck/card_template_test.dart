import 'dart:convert';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smartman/database/database.dart';
import 'package:smartman/deck/deck.dart';
import 'package:smartman/deck/src/card_kind.dart';

/// A card's stored template, its version, and its sides as stored.
typedef _Stored = ({
  String? template,
  int? templateVersion,
  List<Object?> front,
  List<Object?> back,
});

void main() {
  late AppDatabase db;
  late DeckRepository repository;
  late Deck deck;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    var ids = 0;
    var blocks = 0;
    var tick = 0;
    repository = DeckRepository(
      db,
      clock: () => DateTime.utc(2026, 1, 1).add(Duration(seconds: tick++)),
      newId: () => 'id-${ids++}',
      newBlockId: () => 'block-${blocks++}',
    );
    deck = await repository.createDeck('French');
  });

  tearDown(() => db.close());

  Future<_Stored> stored(String id) async {
    final row = await (db.select(
      db.cards,
    )..where((card) => card.id.equals(id))).getSingle();
    return (
      template: row.template,
      templateVersion: row.templateVersion,
      front: jsonDecode(row.front) as List<Object?>,
      back: jsonDecode(row.back) as List<Object?>,
    );
  }

  Card saved(SaveCardResult result) => switch (result) {
    CardSaved(:final card) => card,
    DuplicateFront() => fail('expected a save, got $result'),
  };

  /// A card as a build from before ADR 0106 wrote it: no template, and
  /// blocks with neither a version nor an id.
  Future<Card> legacy(String id, String front, String back) async {
    await db
        .into(db.cards)
        .insert(
          CardsCompanion.insert(
            id: id,
            deckId: deck.id.value,
            front: front,
            back: back,
            cardKey: id,
            source: 'manual',
            createdAt: DateTime.utc(2026),
            updatedAt: DateTime.utc(2026),
          ),
        );
    return (await repository.listCards(deck.id))
        .singleWhere((card) => card.id.value == id);
  }

  test('a card added records the template of the kind it was written in, at '
      'v1, and the one its front derives when none is named', () async {
    final flip = saved(
      await repository.addCard(
        deck.id,
        front: [const TextContent('chat')],
        back: [const TextContent('cat')],
        kind: CardKind.basic,
      ),
    );
    final cloze = saved(
      await repository.addCard(
        deck.id,
        front: [
          const ClozeContent('___ is in France', ['Paris']),
        ],
        back: [const TextContent('Paris is in France')],
        kind: CardKind.cloze,
      ),
    );
    final derived = saved(
      await repository.addCard(
        deck.id,
        front: [
          const TextContent('Capitals'),
          const TableContent(
            columns: ['Capital'],
            rows: [
              ['Paris'],
            ],
            blanks: [(row: 0, column: 0)],
          ),
        ],
        back: [const TextContent('Capitals\nCapital\nParis')],
      ),
    );

    expect(
      [
        for (final card in [flip, cloze, derived])
          (
            (await stored(card.id.value)).template,
            (await stored(card.id.value)).templateVersion,
          ),
      ],
      [('flip', 1), ('cloze', 1), ('table', 1)],
    );
    expect((flip.template, flip.templateVersion), ('flip', 1));

    // The kind the editor names is recorded even where the front would
    // derive another, as a template that only seeds the editor may.
    final named = saved(
      await repository.addCard(
        deck.id,
        front: [const TextContent('Capitals')],
        back: [const TextContent('Paris')],
        kind: CardKind.table,
      ),
    );
    expect(derivedKind(named.front), CardKind.basic);
    expect((await stored(named.id.value)).template, 'table');
  });

  test('every block written carries v1 and an id, and keeps its id through an '
      'edit of its content', () async {
    final card = saved(
      await repository.addCard(
        deck.id,
        front: [const TextContent('chat')],
        back: [
          const SensesContent([CardSense(meaning: 'cat')]),
          const TextContent('extras'),
        ],
        kind: CardKind.basic,
      ),
    );
    final before = await stored(card.id.value);
    expect(before.front, [
      {
        'type': 'text',
        'v': 1,
        'id': 'block-0',
        'payload': {'text': 'chat'},
      },
    ]);
    expect([for (final block in before.back) (block! as Map)['v']], [1, 1]);

    saved(
      await repository.editCard(
        card,
        front: [const TextContent('chatte')],
        back: [
          const SensesContent([CardSense(meaning: 'she-cat')]),
          const TextContent('extras'),
        ],
        kind: CardKind.basic,
      ),
    );
    final after = await stored(card.id.value);
    expect(
      [
        for (final block in [...after.front, ...after.back])
          (block! as Map)['id'],
      ],
      [
        for (final block in [...before.front, ...before.back])
          (block! as Map)['id'],
      ],
      reason: 'each block keeps its id though its content changed',
    );
  });

  test('a card from before templates is read by derivation and gets its '
      'template, and ids on its blocks, on its next write', () async {
    final card = await legacy(
      'old',
      '[{"type":"cloze","payload":{"text":"___ is in France",'
          '"answers":["Paris"]}}]',
      '[{"type":"text","payload":{"text":"Paris is in France"}}]',
    );
    expect((card.template, card.templateVersion), (null, null));
    expect(kindOf(card), CardKind.cloze, reason: 'derived from its front');
    expect(
      (await stored('old')).template,
      isNull,
      reason: 'reading rewrites nothing',
    );

    saved(await repository.editCard(card, front: card.front, back: card.back));
    final after = await stored('old');
    expect((after.template, after.templateVersion), ('cloze', 1));
    expect((after.front.single! as Map)['v'], 1);
    expect((after.front.single! as Map)['id'], isA<String>());
  });

  test(
    'a template or a template version this build does not know opens '
    'nothing, and a merged back keeps them and the unknown block as stored',
    () async {
      const unknownBlock =
          '{"type":"image","v":3,"id":"img","payload":{"media":"m1"},'
          '"boxes":[1,2]}';
      await db
          .into(db.cards)
          .insert(
            CardsCompanion.insert(
              id: 'new',
              deckId: deck.id.value,
              front: '[$unknownBlock]',
              back: '[{"type":"text","v":1,"id":"t","payload":{"text":"cat"}}]',
              cardKey: 'chat',
              source: 'manual',
              template: const Value('image_occlusion'),
              templateVersion: const Value(2),
              createdAt: DateTime.utc(2026),
              updatedAt: DateTime.utc(2026),
            ),
          );
      final card = (await repository.listCards(deck.id)).single;
      expect(kindOf(card), isNull, reason: 'read-only in the editor');
      expect(
        kindOf(
          Card(
            id: card.id,
            deckId: card.deckId,
            front: card.front,
            back: card.back,
            cardKey: card.cardKey,
            source: card.source,
            createdAt: card.createdAt,
            updatedAt: card.updatedAt,
            template: 'flip',
            templateVersion: 2,
          ),
        ),
        isNull,
        reason: 'a known template at a later version is read-only too',
      );

      // Photo import merges a back into it: the only write the app makes to
      // such a card.
      await repository.addCards(AddToDeck(deck.id), [
        const IncomingCard(
          front: [TextContent('chat')],
          back: [TextContent('a cat')],
          onDuplicate: DuplicateChoice.mergeBack,
        ),
      ]);
      final after = await db.select(db.cards).getSingle();
      expect((after.template, after.templateVersion), ('image_occlusion', 2));
      expect(after.front, '[$unknownBlock]', reason: 'byte for byte');
      expect(
        [for (final block in jsonDecode(after.back) as List) block['id']],
        ['t', isA<String>()],
        reason: 'the merged line is a new block',
      );
    },
  );

  test('a photo-imported card is stored with v1 on every block and the '
      'template its front derives', () async {
    await repository.addCards(AddToDeck(deck.id), [
      const IncomingCard(
        front: [
          ClozeContent('___ is in France', ['Paris']),
        ],
        back: [TextContent('Paris is in France')],
        onDuplicate: DuplicateChoice.mergeBack,
      ),
    ]);
    final row = await db.select(db.cards).getSingle();
    expect((row.template, row.templateVersion), ('cloze', 1));
    for (final side in [row.front, row.back]) {
      expect(side, contains('"v":1'));
      for (final block in jsonDecode(side) as List) {
        expect(block['v'], 1, reason: side);
      }
    }
  });
}
