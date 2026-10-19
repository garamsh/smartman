import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:smartman/deck/src/content.dart';

void main() {
  group('content encoding', () {
    test('round-trips a text block with its type discriminator', () {
      const blocks = [TextContent('bonjour')];

      final encoded = encodeContent(blocks);

      expect(encoded, '[{"type":"text","payload":{"text":"bonjour"}}]');
      expect(decodeContent(encoded), blocks);
    });

    test('decodes an unknown type as unsupported and re-encodes it intact', () {
      const stored =
          '[{"type":"text","payload":{"text":"cat"}},'
          '{"type":"image","payload":{"path":"cat.png"}}]';

      final blocks = decodeContent(stored);

      expect(blocks.first, const TextContent('cat'));
      final unsupported = blocks.last;
      expect(unsupported, isA<UnsupportedContent>());
      expect((unsupported as UnsupportedContent).type, 'image');
      expect(encodeContent(blocks), stored);
    });

    test(
      'round-trips a cloze and a table block, as typed blocks beside text',
      () {
        const blocks = [
          TextContent('Capitals'),
          ClozeContent('___ is in France', ['Paris']),
          TableContent(
            columns: ['Capital', 'Country'],
            rows: [
              ['Paris', 'France'],
            ],
            blanks: [(row: 0, column: 0)],
          ),
        ];

        final encoded = encodeContent(blocks);

        expect(
          encoded,
          '[{"type":"text","payload":{"text":"Capitals"}},'
          '{"type":"cloze","payload":{"text":"___ is in France",'
          '"answers":["Paris"]}},'
          '{"type":"table","payload":{"columns":["Capital","Country"],'
          '"rows":[["Paris","France"]],"blanks":[{"row":0,"column":0}]}}]',
        );
        expect(decodeContent(encoded), blocks);
      },
    );

    test('rejects a cloze or a table that breaks its shape, where a whole one '
        'decodes', () {
      String cloze(Object? answers) => jsonEncode([
        {
          'type': 'cloze',
          'payload': {'text': '___ and ___', 'answers': answers},
        },
      ]);
      String table(Object? rows, Object? blanks) => jsonEncode([
        {
          'type': 'table',
          'payload': {
            'columns': ['a', 'b'],
            'rows': rows,
            'blanks': blanks,
          },
        },
      ]);
      final ok = [
        ['1', '2'],
      ];
      final cell = [
        {'row': 0, 'column': 1},
      ];
      for (final broken in [
        cloze(['one']),
        cloze(['one', ' ']),
        cloze('one'),
        table([
          ['1'],
        ], cell),
        table(ok, <Object>[]),
        table(ok, [
          {'row': 1, 'column': 0},
        ]),
        table([
          ['1', ''],
        ], cell),
        table(ok, [...cell, ...cell]),
      ]) {
        expect(
          () => decodeContent(broken),
          throwsFormatException,
          reason: broken,
        );
      }
      // Control: each whole.
      expect(decodeContent(cloze(['one', 'two'])).single, isA<ClozeContent>());
      expect(decodeContent(table(ok, cell)).single, isA<TableContent>());
    });

    test('a cloze and a table read as their filled text, which the card key '
        'takes, and only they make a whole card', () {
      const cloze = ClozeContent('___ is in ___', ['Paris', 'France']);
      const table = TableContent(
        columns: ['Capital', 'Country'],
        rows: [
          ['Paris', 'France'],
        ],
        blanks: [(row: 0, column: 0)],
      );

      expect(plainText([cloze]), 'Paris is in France');
      expect(
        plainText([const TextContent('Capitals'), table]),
        'Capitals\nCapital | Country\nParis | France',
      );
      expect(isWholeCard([cloze]), isTrue);
      expect(isWholeCard([const TextContent('Capitals'), table]), isTrue);
      // Control: text alone, a v6 cloze's "___" included, is split.
      expect(isWholeCard([const TextContent('___ is in France')]), isFalse);
    });

    test('rejects a text block without text as a format error', () {
      expect(
        () => decodeContent('[{"type":"text","payload":{}}]'),
        throwsFormatException,
      );
    });
  });
}
