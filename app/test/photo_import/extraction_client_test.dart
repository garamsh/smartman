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

/// A vocabulary card of one sense as the function sends it today.
Map<String, Object?> _vocabulary(
  String front,
  String meaning, [
  Map<String, Object?> fields = const {},
]) => {
  'kind': 'vocabulary',
  'type': 'concept',
  'front': front,
  'answer': meaning,
  'topic': 'Page',
  'senses': [
    {'labels': <Object>[], 'meaning': meaning, 'examples': <Object>[]},
  ],
  ...fields,
};

/// A note card as the function sends it today.
Map<String, Object?> _note(
  String front,
  String answer, [
  Map<String, Object?> fields = const {},
]) => {
  'kind': 'note',
  'type': 'concept',
  'front': front,
  'answer': answer,
  'topic': 'Page',
  ...fields,
};

void main() {
  test(
    'posts the photo as base64 JPEG with the user token and returns the cards',
    () async {
      late http.Request sent;
      final client = _client((request) async {
        sent = request;
        return _json(200, {
          'cards': [_vocabulary('chat', 'cat'), _vocabulary(' chien ', 'dog')],
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

  test('a card of an older function, without an answer, a topic, a kind or a '
      "vocabulary card's senses, is a service failure: its back, meaning and "
      'part of speech no longer stand in for them', () async {
    for (final card in <Map<String, Object?>>[
      {'front': 'chat', 'back': 'cat'},
      {..._vocabulary('chat', 'cat')}..remove('answer'),
      {..._vocabulary('chat', 'cat')}..remove('topic'),
      {..._vocabulary('chat', 'cat')}..remove('kind'),
      {..._vocabulary('chat', 'cat'), 'meaning': 'cat', 'partOfSpeech': '[명]'}
        ..remove('senses'),
    ]) {
      final client = _client(
        (_) async => _json(200, {
          'cards': [card],
        }),
      );
      await expectLater(
        _extract(client),
        throwsA(isA<ServiceFailed>()),
        reason: '$card',
      );
    }
    // Control: the same card as the function sends it today.
    final client = _client(
      (_) async => _json(200, {
        'cards': [_vocabulary('chat', 'cat')],
      }),
    );
    expect((await _extract(client))!.single.senses, [
      const CardSense(meaning: 'cat'),
    ]);
  });

  test(
    "a card reads its kind, type, senses in order, extras and pronunciation, "
    "and a note none of a vocabulary card's fields",
    () async {
      final client = _client(
        (_) async => _json(200, {
          'cards': [
            _vocabulary('face', '[동] [구어] 직면하다\n표면', {
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
            }),
            _note("'이는 책이다'의 '이'", '대명사', {'type': 'identify'}),
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
    Map<String, Object?> card(Map<String, Object?> fields) =>
        _vocabulary('face', '표면', fields);
    for (final fields in <Map<String, Object?>>[
      {'kind': 'grammar'},
      {'senses': <Object>[]},
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
          card({'type': 'identify'}),
        ],
      }),
    );
    expect((await _extract(valid))!.single.type, CardType.identify);
  });

  test('a type this version does not know is read as a concept card with its '
      'front and answer, so a new type does not fail the extraction', () async {
    final client = _client(
      (_) async => _json(200, {
        'cards': [
          for (final type in ['judgment', 1])
            _note('양성모음', 'ㅏ ㅗ', {
              'type': type,
              'table': {'columns': <String>[]},
            }),
          // Control: a known type keeps its own.
          _note("'아름다운'의 '아'", '양성모음', {'type': 'identify'}),
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
    'and one without its field is a service failure',
    () async {
      final tableCard = _note('인칭 대명사', '구분 | 높임\n2인칭 | 당신', {
        'type': 'table',
        'table': {
          'columns': ['구분', '높임'],
          'rows': [
            ['2인칭', '당신'],
          ],
          'blanks': [
            {'row': 0, 'column': 1},
          ],
        },
      });
      final clozeCard = _note('높임 ___ · 낮춤 ___', '당신\n너', {
        'type': 'cloze',
        'cloze': {
          'answers': ['당신', '너'],
        },
      });
      final client = _client(
        (_) async => _json(200, {
          'cards': [tableCard, clozeCard],
        }),
      );

      final [table, cloze] = (await _extract(client))!;

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
      // Prompt v6's cloze card, without its cloze, and a table card without
      // its table, are refused.
      for (final card in [
        {...clozeCard}..remove('cloze'),
        {...tableCard}..remove('table'),
      ]) {
        final without = _client(
          (_) async => _json(200, {
            'cards': [card],
          }),
        );
        await expectLater(
          _extract(without),
          throwsA(isA<ServiceFailed>()),
          reason: '$card',
        );
      }
    },
  );

  test('a cloze whose answers do not match its blanks, or a table with a blank '
      'outside it, is a service failure', () async {
    Future<List<CandidateCard>?> extract(Map<String, Object?> fields) =>
        _extract(
          _client(
            (_) async => _json(200, {
              'cards': [_note('높임 ___', '당신', fields)],
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

  test('a card reads its topic and examples, and none when the page prints '
      'no examples', () async {
    final client = _client(
      (_) async => _json(200, {
        'cards': [
          _note('양성모음', 'ㅏ ㅗ ㅑ ㅛ', {
            'examples': [' 밝고 가벼운 느낌 '],
            'topic': ' 모음조화 ',
          }),
          _vocabulary('chat', 'cat'),
        ],
      }),
    );

    final [vowels, chat] = (await _extract(client))!;

    expect((vowels.topic, vowels.answer), ('모음조화', 'ㅏ ㅗ ㅑ ㅛ'));
    expect(vowels.examples, ['밝고 가벼운 느낌']);
    expect(chat.topic, 'Page');
    expect(chat.examples, isEmpty);
  });

  test('each refusal the contract names maps to its failure', () async {
    final cases = <(int, Map<String, Object?>), Matcher>{
      (401, {'error': 'unauthenticated'}): isA<SignInRequired>(),
      (413, {'error': 'too_large'}): isA<PhotoRefused>(),
      (415, {'error': 'unsupported_type'}): isA<PhotoRefused>(),
      (422, {'error': 'no_cards'}): isA<NoCardsFound>(),
      (429, {'error': 'rate_limited', 'daily_limit': 30}):
          isA<DailyLimitReached>(),
      (502, {'error': 'model_error'}): isA<ModelFailed>(),
      (503, {'error': 'not_configured'}): isA<ServiceFailed>(),
      (403, {'error': 'suspended'}): isA<AccountSuspendedFailure>(),
      (403, {'error': 'forbidden'}): isA<ServiceFailed>(),
      (400, {'error': 'bad_request'}): isA<ServiceFailed>(),
      (500, {'error': 'internal'}): isA<ServiceFailed>(),
    };
    for (final MapEntry(key: (status, body), value: matcher) in cases.entries) {
      final client = _client((_) async => _json(status, body));
      await expectLater(_extract(client), throwsA(matcher), reason: '$body');
    }
  });

  test(
    "a daily limit's refusal carries the plan's limit the body states, and "
    'a 429 without one, as a gateway might send, is a service failure',
    () async {
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
      for (final body in <Object>[
        {'error': 'rate_limited'},
        {'error': 'rate_limited', 'daily_limit': -1},
        {'error': 'rate_limited', 'daily_limit': '100'},
        'Too Many Requests',
      ]) {
        final unstated = _client(
          (_) async =>
              body is String ? http.Response(body, 429) : _json(429, body),
        );
        await expectLater(
          _extract(unstated),
          throwsA(isA<ServiceFailed>()),
          reason: '$body',
        );
      }
    },
  );

  test('a success body outside the contract is a service failure', () async {
    for (final body in [
      'not json',
      jsonEncode({'cards': <Object>[]}),
      jsonEncode({
        'cards': [_vocabulary('chat', '  ')],
      }),
      jsonEncode({
        'cards': [
          {'front': 'chat'},
        ],
      }),
      for (final examples in <Object?>[
        'a cat',
        ['a cat', ''],
      ])
        jsonEncode({
          'cards': [
            _vocabulary('chat', 'cat', {'examples': examples}),
          ],
        }),
      for (final topic in <Object?>['', '  ', 7, 'a' * 61])
        jsonEncode({
          'cards': [
            _vocabulary('chat', 'cat', {'topic': topic}),
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
            _vocabulary('chat', 'cat', {'topic': 'a' * 60}),
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
