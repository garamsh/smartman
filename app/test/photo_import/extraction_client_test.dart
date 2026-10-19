import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:image/image.dart' as img;
import 'package:smartman/deck/deck.dart';
import 'package:smartman/photo_import/photo_import.dart';
import 'package:smartman/photo_import/src/photo.dart';

final _url = Uri.parse(
  'https://project.supabase.co/functions/v1/extract-cards',
);

final _photo = downscalePhoto(img.encodePng(img.Image(width: 4, height: 3)));

HttpExtractionClient _client(
  MockClientHandler handler, {
  String? token = 'user-token',
}) => HttpExtractionClient(
  MockClient(handler),
  functionUrl: _url,
  accessToken: () async => token,
);

/// A JSON answer as the function sends it: UTF-8, typed `application/json`.
http.Response _json(int status, Object body) => http.Response.bytes(
  utf8.encode(jsonEncode(body)),
  status,
  headers: {'content-type': 'application/json'},
);

Future<List<CandidateCard>?> _extract(HttpExtractionClient client) =>
    client.extract(_photo, cancel: Completer<void>().future);

void main() {
  test(
    'posts the photo as base64 JPEG with the user token and returns the cards',
    () async {
      late http.Request sent;
      final client = _client((request) async {
        sent = request;
        return _json(200, {
          'cards': [
            {'front': 'chat', 'back': 'cat'},
            {'front': ' chien ', 'back': 'dog'},
          ],
        });
      });

      final cards = await _extract(client);

      expect(sent.method, 'POST');
      expect(sent.url, _url);
      expect(sent.headers['authorization'], 'Bearer user-token');
      expect(sent.headers['content-type'], startsWith('application/json'));
      final body = jsonDecode(sent.body) as Map<String, Object?>;
      expect(body.keys, ['image']);
      expect(base64Decode(body['image']! as String), _photo.bytes);
      expect(cards!.map((card) => (card.front, card.answer)), [
        ('chat', 'cat'),
        ('chien', 'dog'),
      ]);
    },
  );

  test('a card takes its answer from answer, else meaning, else back, with the '
      'part of speech the page prints', () async {
    final client = _client(
      (_) async => _json(200, {
        'cards': [
          {
            'front': 'run',
            'back': '[동] 달리다, 운영하다',
            'answer': ' 달리다, 운영하다 ',
            'meaning': '달리다, 운영하다',
            'partOfSpeech': '[동]',
          },
          {'front': 'river', 'back': '강', 'meaning': ' 강 '},
          {'front': 'chat', 'back': 'n. cat'},
        ],
      }),
    );

    final [run, river, chat] = (await _extract(client))!;

    // A function before senses: one sense of the answer and its label.
    expect(
      (run.front, run.answer, run.kind),
      ('run', '달리다, 운영하다', CardKind.vocabulary),
    );
    // Its label, without its brackets, a part of speech's short form.
    expect(run.senses, [
      const CardSense(
        labels: [PartOfSpeechLabel(PartOfSpeech.verb, '동')],
        meaning: '달리다, 운영하다',
      ),
    ]);
    expect(river.senses, [const CardSense(meaning: '강')]);
    expect(chat.senses, [const CardSense(meaning: 'n. cat')]);
  });

  test(
    "a card reads its kind, type, senses in order, extras and pronunciation, "
    "and a note none of a vocabulary card's fields",
    () async {
      final client = _client(
        (_) async => _json(200, {
          'cards': [
            {
              'kind': 'vocabulary',
              'type': 'concept',
              'front': 'face',
              'back': '[동] 직면하다\n[명] 표면',
              'senses': [
                {
                  'labels': [
                    {'kind': 'part_of_speech', 'category': 'verb', 'text': '동'},
                    {'kind': 'other', 'category': null, 'text': '구어'},
                  ],
                  'meaning': ' 직면하다 ',
                  'examples': [' face the music '],
                },
                {'labels': <Object>[], 'meaning': '표면', 'examples': <Object>[]},
              ],
              'extras': [
                {'label': '유의어', 'text': 'confront'},
              ],
              'pronunciation': "['feis]",
            },
            {
              'kind': 'note',
              'type': 'identify',
              'front': "'이는 책이다'의 '이'",
              'answer': '대명사',
              'back': '대명사',
            },
          ],
        }),
      );

      final [face, judge] = (await _extract(client))!;

      expect((face.kind, face.type), (CardKind.vocabulary, CardType.concept));
      expect(face.senses, [
        const CardSense(
          labels: [PartOfSpeechLabel(PartOfSpeech.verb, '동'), OtherLabel('구어')],
          meaning: '직면하다',
          examples: ['face the music'],
        ),
        const CardSense(meaning: '표면'),
      ]);
      expect(face.extras.map((extra) => (extra.label, extra.text)), [
        ('유의어', 'confront'),
      ]);
      expect(face.pronunciation, "['feis]");
      expect((judge.kind, judge.type), (CardKind.note, CardType.identify));
      expect(judge.answer, '대명사');
      expect(judge.senses, isEmpty);
      expect(judge.pronunciation, isNull);
    },
  );

  test('an unknown kind, a vocabulary card with no sense, or a '
      'malformed sense or extra is a service failure', () async {
    Map<String, Object?> card(Map<String, Object?> fields) => {
      'front': 'face',
      'back': '표면',
      ...fields,
    };
    for (final fields in <Map<String, Object?>>[
      {'kind': 'grammar'},
      {'kind': 'vocabulary', 'senses': <Object>[]},
      // A sense without its meaning, with a label of an unknown kind or
      // category, an other label with a category, or the old {pos, meaning}.
      for (final sense in <Map<String, Object?>>[
        {'labels': <Object>[], 'examples': <Object>[]},
        {
          'labels': [
            {'kind': 'gender', 'category': null, 'text': 'der'},
          ],
          'meaning': '표면',
          'examples': <Object>[],
        },
        {
          'labels': [
            {'kind': 'part_of_speech', 'category': 'gerund', 'text': 'ger.'},
          ],
          'meaning': '표면',
          'examples': <Object>[],
        },
        {
          'labels': [
            {'kind': 'other', 'category': 'noun', 'text': '사물'},
          ],
          'meaning': '표면',
          'examples': <Object>[],
        },
        {'pos': '[명]', 'meaning': '표면'},
      ])
        {
          'senses': [sense],
        },
      {'senses': 'a'},
      {
        'extras': [
          {'label': '유의어'},
        ],
      },
      {'pronunciation': ' '},
    ]) {
      final client = _client(
        (_) async => _json(200, {
          'cards': [card(fields)],
        }),
      );
      await expectLater(
        _extract(client),
        throwsA(isA<ServiceFailed>()),
        reason: '$fields',
      );
    }
    // Control: the same card with a known kind and type and a sense.
    final valid = _client(
      (_) async => _json(200, {
        'cards': [
          card({
            'kind': 'vocabulary',
            'type': 'cloze',
            'senses': [
              {'labels': <Object>[], 'meaning': '표면', 'examples': <Object>[]},
            ],
          }),
        ],
      }),
    );
    expect((await _extract(valid))!.single.type, CardType.cloze);
  });

  test('a type this version does not know is read as a concept card with its '
      'front and answer, so a new type does not fail the extraction', () async {
    final client = _client(
      (_) async => _json(200, {
        'cards': [
          for (final type in ['judgment', 1])
            {
              'kind': 'note',
              'type': type,
              'front': '양성모음',
              'answer': 'ㅏ ㅗ',
              'back': 'ㅏ ㅗ',
              'table': {'columns': <String>[]},
            },
          // Control: a known type keeps its own.
          {
            'kind': 'note',
            'type': 'identify',
            'front': "'아름다운'의 '아'",
            'answer': '양성모음',
            'back': '양성모음',
          },
        ],
      }),
    );

    final cards = (await _extract(client))!;

    expect(
      [for (final card in cards) card.type],
      [CardType.concept, CardType.concept, CardType.identify],
    );
    expect(
      [for (final card in cards.take(2)) (card.front, card.answer)],
      [('양성모음', 'ㅏ ㅗ'), ('양성모음', 'ㅏ ㅗ')],
    );
    expect(cards.map((card) => card.wholeFront), everyElement(isNull));
  });

  test(
    "a table card's table and a cloze card's cloze become its front's blocks, "
    "where a cloze card without one, from prompt v6, stays a plain card",
    () async {
      final client = _client(
        (_) async => _json(200, {
          'cards': [
            {
              'kind': 'note',
              'type': 'table',
              'front': '인칭 대명사',
              'answer': '구분 | 높임\n2인칭 | 당신',
              'back': '구분 | 높임\n2인칭 | 당신',
              'table': {
                'columns': ['구분', '높임'],
                'rows': [
                  ['2인칭', '당신'],
                ],
                'blanks': [
                  {'row': 0, 'column': 1},
                ],
              },
            },
            {
              'kind': 'note',
              'type': 'cloze',
              'front': '높임 ___ · 낮춤 ___',
              'answer': '당신\n너',
              'back': '당신\n너',
              'cloze': {
                'answers': ['당신', '너'],
              },
            },
            {
              'kind': 'note',
              'type': 'cloze',
              'front': '높임 ___ · 낮춤 너',
              'answer': '당신',
              'back': '당신',
            },
          ],
        }),
      );

      final [table, cloze, v6] = (await _extract(client))!;

      expect(table.type, CardType.table);
      expect(table.wholeFront, [
        const TextContent('인칭 대명사'),
        const TableContent(
          columns: ['구분', '높임'],
          rows: [
            ['2인칭', '당신'],
          ],
          blanks: [(row: 0, column: 1)],
        ),
      ]);
      expect(cloze.wholeFront, [
        const ClozeContent('높임 ___ · 낮춤 ___', ['당신', '너']),
      ]);
      expect(v6.type, CardType.cloze);
      expect(v6.wholeFront, isNull);
      expect((v6.front, v6.answer), ('높임 ___ · 낮춤 너', '당신'));
    },
  );

  test('a cloze whose answers do not match its blanks, or a table with a blank '
      'outside it, is a service failure', () async {
    Future<List<CandidateCard>?> extract(Map<String, Object?> fields) =>
        _extract(
          _client(
            (_) async => _json(200, {
              'cards': [
                {'kind': 'note', 'front': '높임 ___', 'back': '당신', ...fields},
              ],
            }),
          ),
        );
    final table = {
      'columns': ['구분', '높임'],
      'rows': [
        ['2인칭', '당신'],
      ],
    };
    for (final fields in <Map<String, Object?>>[
      {
        'type': 'cloze',
        'cloze': {
          'answers': ['당신', '너'],
        },
      },
      {
        'type': 'table',
        'table': {
          ...table,
          'blanks': [
            {'row': 1, 'column': 1},
          ],
        },
      },
    ]) {
      await expectLater(
        extract(fields),
        throwsA(isA<ServiceFailed>()),
        reason: '$fields',
      );
    }
    // Control: each with its blanks inside.
    for (final fields in <Map<String, Object?>>[
      {
        'type': 'cloze',
        'cloze': {
          'answers': ['당신'],
        },
      },
      {
        'type': 'table',
        'table': {
          ...table,
          'blanks': [
            {'row': 0, 'column': 1},
          ],
        },
      },
    ]) {
      expect((await extract(fields))!.single.wholeFront, isNotNull);
    }
  });

  test(
    "a card reads its topic and examples, none from a function that names "
    "none, and no longer checks the step or short form it does not show",
    () async {
      final client = _client(
        (_) async => _json(200, {
          'cards': [
            {
              'kind': 'note',
              'front': '양성모음',
              'answer': 'ㅏ ㅗ ㅑ ㅛ',
              'short': 'ㅏ ㅗ',
              'step': 9,
              'examples': [' 밝고 가벼운 느낌 '],
              'back': 'ㅏ ㅗ ㅑ ㅛ',
              'topic': ' 모음조화 ',
            },
            {'front': 'chat', 'back': 'cat'},
          ],
        }),
      );

      final [vowels, chat] = (await _extract(client))!;

      expect((vowels.topic, vowels.answer), ('모음조화', 'ㅏ ㅗ ㅑ ㅛ'));
      expect(vowels.examples, ['밝고 가벼운 느낌']);
      expect(chat.topic, isNull);
      expect(chat.examples, isEmpty);
    },
  );

  test('each refusal the contract names maps to its failure', () async {
    final cases = <(int, String), Matcher>{
      (401, 'unauthenticated'): isA<SignInRequired>(),
      (413, 'too_large'): isA<PhotoRefused>(),
      (415, 'unsupported_type'): isA<PhotoRefused>(),
      (422, 'no_cards'): isA<NoCardsFound>(),
      (429, 'rate_limited'): isA<DailyLimitReached>(),
      (502, 'model_error'): isA<ModelFailed>(),
      (503, 'not_configured'): isA<ServiceFailed>(),
      (403, 'suspended'): isA<AccountSuspendedFailure>(),
      (403, 'forbidden'): isA<ServiceFailed>(),
      (400, 'bad_request'): isA<ServiceFailed>(),
      (500, 'internal'): isA<ServiceFailed>(),
    };
    for (final MapEntry(key: (status, code), value: matcher) in cases.entries) {
      final client = _client((_) async => _json(status, {'error': code}));
      await expectLater(_extract(client), throwsA(matcher), reason: code);
    }
  });

  test("a daily limit's refusal carries the plan's limit the body states, and none from a body without it", () async {
    final stated = _client(
      (_) async => _json(429, {'error': 'rate_limited', 'daily_limit': 100}),
    );
    await expectLater(
      _extract(stated),
      throwsA(
        isA<DailyLimitReached>().having(
          (failure) => failure.dailyLimit,
          'dailyLimit',
          100,
        ),
      ),
    );
    for (final body in [
      {'error': 'rate_limited'},
      {'error': 'rate_limited', 'daily_limit': -1},
      {'error': 'rate_limited', 'daily_limit': '100'},
    ]) {
      final unstated = _client((_) async => _json(429, body));
      await expectLater(
        _extract(unstated),
        throwsA(
          isA<DailyLimitReached>().having(
            (failure) => failure.dailyLimit,
            'dailyLimit',
            isNull,
          ),
        ),
        reason: '$body',
      );
    }
  });

  test('a success body outside the contract is a service failure', () async {
    for (final body in [
      'not json',
      jsonEncode({'cards': <Object>[]}),
      jsonEncode({
        'cards': [
          {'front': 'chat', 'back': '  '},
        ],
      }),
      jsonEncode({
        'cards': [
          {'front': 'chat'},
        ],
      }),
      for (final field in <String, Object?>{
        'answer': ' ',
        'meaning': ' ',
        'partOfSpeech': 1,
      }.entries)
        jsonEncode({
          'cards': [
            {'front': 'chat', 'back': 'cat', field.key: field.value},
          ],
        }),
      for (final examples in <Object?>[
        'a cat',
        ['a cat', ''],
      ])
        jsonEncode({
          'cards': [
            {'front': 'chat', 'back': 'cat', 'examples': examples},
          ],
        }),
      for (final topic in <Object?>['', '  ', 7, 'a' * 61])
        jsonEncode({
          'cards': [
            {'front': 'chat', 'back': 'cat', 'topic': topic},
          ],
        }),
    ]) {
      final client = _client((_) async => http.Response(body, 200));
      await expectLater(
        _extract(client),
        throwsA(isA<ServiceFailed>()),
        reason: body,
      );
    }
    // Control: a topic of the most characters the contract allows is read.
    final longest = _client(
      (_) async => http.Response(
        jsonEncode({
          'cards': [
            {'front': 'chat', 'back': 'cat', 'topic': 'a' * 60},
          ],
        }),
        200,
      ),
    );
    expect((await _extract(longest))!.single.topic, 'a' * 60);
  });

  test('a request that cannot reach the server is offline', () async {
    final client = _client(
      (request) async => throw http.ClientException('no route', request.url),
    );

    await expectLater(_extract(client), throwsA(isA<ExtractionOffline>()));
  });

  test('without a session nothing is sent and sign-in is required', () async {
    var sent = 0;
    final client = _client((_) async {
      sent++;
      return _json(200, {});
    }, token: null);

    await expectLater(_extract(client), throwsA(isA<SignInRequired>()));
    expect(sent, 0);
  });

  test('cancelling aborts the request and returns no cards', () async {
    final cancel = Completer<void>();
    final aborted = Completer<void>();
    final client = HttpExtractionClient(
      MockClient.streaming((request, _) async {
        // MockClient leaves aborting to its handler, as a real client does it.
        await (request as http.Abortable).abortTrigger;
        aborted.complete();
        throw http.RequestAbortedException(request.url);
      }),
      functionUrl: _url,
      accessToken: () async => 'user-token',
    );

    final result = client.extract(_photo, cancel: cancel.future);
    cancel.complete();

    expect(await result, isNull);
    expect(aborted.isCompleted, isTrue);
  });

  test('the function URL is the PostgREST URL with its suffix swapped', () {
    // The Supabase client appends '/rest/v1' to the project URL as given.
    for (final (project, expected) in [
      (
        'https://abc.supabase.co',
        'https://abc.supabase.co/functions/v1/extract-cards',
      ),
      (
        'https://abc.supabase.co/',
        'https://abc.supabase.co//functions/v1/extract-cards',
      ),
      (
        'https://gateway.example/prefix',
        'https://gateway.example/prefix/functions/v1/extract-cards',
      ),
    ]) {
      expect(
        extractCardsUrl('$project/rest/v1'),
        Uri.parse(expected),
        reason: project,
      );
    }
    // Control: a URL that is not a PostgREST URL is refused, not guessed.
    expect(
      () => extractCardsUrl('https://abc.supabase.co/auth/v1'),
      throwsArgumentError,
    );
  });
}
