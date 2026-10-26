import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:smartman/deck/src/content.dart';

void main() {
  group('content encoding', () {
    test('round-trips a text block with its type discriminator', () {
      const blocks = [TextContent('bonjour')];

      final encoded = encodeContent(blocks);

      expect(encoded, '[{"type":"text","v":1,"payload":{"text":"bonjour"}}]');
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
      // The text block is written at this build's version; the image block
      // as it was stored.
      expect(
        encodeContent(blocks),
        '[{"type":"text","v":1,"payload":{"text":"cat"}},'
        '{"type":"image","payload":{"path":"cat.png"}}]',
      );
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
          '[{"type":"text","v":1,"payload":{"text":"Capitals"}},'
          '{"type":"cloze","v":1,"payload":{"text":"___ is in France",'
          '"answers":["Paris"]}},'
          '{"type":"table","v":1,"payload":{"columns":["Capital","Country"],'
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
        '[{"type":"senses","v":1,"payload":{"senses":['
        '{"labels":[{"kind":"part_of_speech","category":"noun","text":"명"},'
        '{"kind":"other","category":null,"text":"사물"}],'
        '"meaning":"기차","examples":["기차를 타다"]},'
        '{"labels":[],"meaning":"열차","examples":[]}]}}]',
      );
      expect(decodeContent(encoded), blocks);
    });

    test("decodes the back the server's senses migration writes, as "
        'supabase/tests/senses_migration_test.sql states it', () {
      const migrated =
          '[{"type": "senses", "payload": {"senses": [{"labels": [{"kind": "part_of_speech", "text": "명", "category": "noun"}], "meaning": "사과", "examples": []}, {"labels": [{"kind": "part_of_speech", "text": "동", "category": "verb"}], "meaning": "먹다", "examples": []}]}}]';

      final blocks = decodeContent(migrated);

      expect(blocks, const [
        SensesContent([
          CardSense(
            labels: [PartOfSpeechLabel(PartOfSpeech.noun, '명')],
            meaning: '사과',
          ),
          CardSense(
            labels: [PartOfSpeechLabel(PartOfSpeech.verb, '동')],
            meaning: '먹다',
          ),
        ]),
      ]);
      expect(plainText(blocks), '[명] 사과\n[동] 먹다');
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

  group('block versions and ids (ADR 0106)', () {
    // One block of each type this build knows, as it writes each at v1.
    const blocks = <(String, Content, String)>[
      ('text', TextContent('bonjour'), '{"text":"bonjour"}'),
      (
        'cloze',
        ClozeContent('___ is in France', ['Paris']),
        '{"text":"___ is in France","answers":["Paris"]}',
      ),
      (
        'table',
        TableContent(
          columns: ['Capital', 'Country'],
          rows: [
            ['Paris', 'France'],
          ],
          blanks: [(row: 0, column: 0)],
        ),
        '{"columns":["Capital","Country"],"rows":[["Paris","France"]],'
            '"blanks":[{"row":0,"column":0}]}',
      ),
      (
        'senses',
        SensesContent([CardSense(meaning: '기차')]),
        '{"senses":[{"labels":[],"meaning":"기차","examples":[]}]}',
      ),
    ];

    for (final (type, block, payload) in blocks) {
      test('a $type block is read at v1 with and without the field, and '
          'written with it', () {
        final without = '[{"type":"$type","payload":$payload}]';
        final withV = '[{"type":"$type","v":1,"payload":$payload}]';

        expect(decodeContent(without), [block], reason: 'no v reads as v1');
        expect(decodeContent(withV), [block]);
        expect(encodeContent([block]), withV);
      });

      test('a $type block above the version this build writes is kept, '
          'byte for byte, as unsupported', () {
        final stored =
            '[{"type":"$type","v":2,"id":"b1","payload":$payload,'
            '"extra":true}]';

        final decoded = decodeContent(stored);

        expect(decoded.single, isA<UnsupportedContent>());
        expect((decoded.single as UnsupportedContent).type, type);
        expect(encodeContent(decoded), stored);
      });
    }

    test('a block keeps its id through a read and a write', () {
      const stored =
          '[{"type":"text","v":1,"id":"0190a8c4-0000-7000-8000-000000000001",'
          '"payload":{"text":"cat"}}]';

      final decoded = decodeContent(stored);

      expect(decoded.single.id, '0190a8c4-0000-7000-8000-000000000001');
      expect(encodeContent(decoded), stored);
      expect(
        decoded.single,
        const TextContent('cat'),
        reason: 'ids are not compared',
      );
    });

    test('a v that is not a positive integer, or an id that is not text, '
        'is a format error, and a v of 1 is not', () {
      for (final broken in [
        '[{"type":"text","v":0,"payload":{"text":"cat"}}]',
        '[{"type":"text","v":"1","payload":{"text":"cat"}}]',
        '[{"type":"text","v":1,"id":7,"payload":{"text":"cat"}}]',
      ]) {
        expect(
          () => decodeContent(broken),
          throwsFormatException,
          reason: broken,
        );
      }
      expect(
        decodeContent(
          '[{"type":"text","v":1,"id":"a","payload":{"text":"x"}}]',
        ),
        [const TextContent('x')],
        reason: 'control',
      );
    });

    test('the upcaster chain upgrades an older payload one step per '
        'version, to the version a type is written at', () {
      // A text block whose v2 renamed text to body, and v3 trimmed it.
      final steps = <String, List<Object? Function(Object?)>>{
        'text': [
          (payload) => {'body': (payload! as Map)['text']},
          (payload) => {'body': ((payload! as Map)['body'] as String).trim()},
        ],
      };

      expect(blockVersion('text', steps: steps), 3);
      expect(upcastPayload('text', 1, {'text': ' cat '}, steps: steps), {
        'body': 'cat',
      });
      expect(upcastPayload('text', 2, {'body': ' cat '}, steps: steps), {
        'body': 'cat',
      }, reason: 'a v2 payload takes the last step only');
      expect(upcastPayload('text', 3, {'body': 'cat'}, steps: steps), {
        'body': 'cat',
      }, reason: 'the current version takes none');
      // Today every type this build knows is written at v1, with no step.
      for (final type in ['text', 'cloze', 'table', 'senses']) {
        expect(blockVersion(type), 1, reason: type);
      }
    });
  });

  group('the face a card is studied on (ADR 0106)', () {
    const text = TextContent('Paris');
    const cloze = ClozeContent('___ is in France', ['Paris']);
    const table = TableContent(
      columns: ['Capital'],
      rows: [
        ['Paris'],
      ],
      blanks: [(row: 0, column: 0)],
    );
    const senses = SensesContent([CardSense(meaning: '파리')]);
    const unknown = UnsupportedContent('image', {'media': 'm1'});

    test('a card with no blank is studied front then back, whatever its '
        'blocks', () {
      for (final block in <Content>[text, senses, unknown]) {
        expect(
          oneFaceOf([block], [text]),
          isNull,
          reason: '$block on the front',
        );
        expect(
          oneFaceOf([text], [block]),
          isNull,
          reason: '$block on the back',
        );
      }
    });

    test('a cloze or a table on the front makes the front the one face', () {
      for (final block in <Content>[cloze, table]) {
        expect(oneFaceOf([text, block], [text]), [text, block]);
        expect(oneFaceOf([block], [block]), [block], reason: 'front first');
      }
    });

    test('a cloze or a table on the back alone makes one face of the front '
        'followed by the back (ADR 0108)', () {
      for (final block in <Content>[cloze, table]) {
        expect(oneFaceOf([text], [senses, block]), [text, senses, block]);
        expect(oneFaceOf(const [], [senses, block]), [
          senses,
          block,
        ], reason: 'an empty front adds nothing');
      }
    });
  });
}
