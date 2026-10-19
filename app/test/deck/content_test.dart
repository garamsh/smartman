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

    test('round-trips a senses block, each sense with its labels, meaning and examples', () {
      const blocks = [
        SensesContent([
          CardSense(
            labels: [
              PartOfSpeechLabel(PartOfSpeech.noun, '명'),
              OtherLabel('사물'),
            ],
            meaning: '기차',
            examples: ['기차를 타다'],
          ),
          CardSense(meaning: '열차'),
        ]),
      ];

      final encoded = encodeContent(blocks);

      expect(
        encoded,
        '[{"type":"senses","payload":{"senses":['
        '{"labels":[{"kind":"part_of_speech","category":"noun","text":"명"},'
        '{"kind":"other","category":null,"text":"사물"}],'
        '"meaning":"기차","examples":["기차를 타다"]},'
        '{"labels":[],"meaning":"열차","examples":[]}]}}]',
      );
      expect(decodeContent(encoded), blocks);
    });

    test(
      'rejects a senses block that breaks its shape, where a whole one decodes',
      () {
        String senses(Object? senses) => jsonEncode([
          {
            'type': 'senses',
            'payload': {'senses': senses},
          },
        ]);
        Map<String, Object?> sense({
          Object? labels = const <Object>[],
          Object? meaning = '사과',
          Object? examples = const <Object>[],
        }) => {'labels': labels, 'meaning': meaning, 'examples': examples};
        for (final broken in [
          senses(<Object>[]),
          senses('사과'),
          senses([sense(meaning: ' ')]),
          senses([sense(meaning: null)]),
          senses([
            sense(examples: [1]),
          ]),
          senses([
            sense(
              labels: [
                {'kind': 'part_of_speech', 'category': 'gerund', 'text': '동'},
              ],
            ),
          ]),
          senses([
            sense(
              labels: [
                {'kind': 'other', 'category': 'noun', 'text': '사물'},
              ],
            ),
          ]),
          senses([
            sense(
              labels: [
                {'kind': 'other', 'category': null, 'text': ''},
              ],
            ),
          ]),
          senses([
            {'pos': '[명]', 'meaning': '사과'},
          ]),
        ]) {
          expect(
            () => decodeContent(broken),
            throwsFormatException,
            reason: broken,
          );
        }
        // Control: a whole one, with a label of each kind.
        expect(
          decodeContent(
            senses([
              sense(
                labels: [
                  {'kind': 'part_of_speech', 'category': 'noun', 'text': '명'},
                  {'kind': 'other', 'category': null, 'text': '사물'},
                ],
              ),
            ]),
          ).single,
          isA<SensesContent>(),
        );
      },
    );

    test(
      'a senses block reads as one line per sense, each label in brackets '
      'and a space before the meaning, a part of speech by its short form',
      () {
        const senses = SensesContent([
          CardSense(
            labels: [PartOfSpeechLabel(PartOfSpeech.verb, 'v.')],
            meaning: '살다, 거주하다',
          ),
          CardSense(
            labels: [PartOfSpeechLabel(PartOfSpeech.adjective, '형')],
            meaning: '살아 있는',
          ),
          CardSense(labels: [OtherLabel('사물')], meaning: '철도 위를 다니는 긴 차'),
          CardSense(meaning: '사과'),
        ]);

        expect(
          plainText([senses]),
          '[동] 살다, 거주하다\n[형] 살아 있는\n[사물] 철도 위를 다니는 긴 차\n사과',
        );
      },
    );

    test('rejects a text block without text as a format error', () {
      expect(
        () => decodeContent('[{"type":"text","payload":{}}]'),
        throwsFormatException,
      );
    });
  });
}
