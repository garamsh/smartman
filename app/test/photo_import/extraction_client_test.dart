import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:image/image.dart' as img;
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
    expect(run.senses, [const Sense(pos: '[동]', meaning: '달리다, 운영하다')]);
    expect(river.senses, [const Sense(meaning: '강')]);
    expect(chat.senses, [const Sense(meaning: 'n. cat')]);
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
                {'pos': '[동]', 'meaning': ' 직면하다 '},
                {'pos': null, 'meaning': '표면'},
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
        const Sense(pos: '[동]', meaning: '직면하다'),
        const Sense(meaning: '표면'),
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

  test('an unknown kind or type, a vocabulary card with no sense, or a '
      'malformed sense or extra is a service failure', () async {
    Map<String, Object?> card(Map<String, Object?> fields) => {
      'front': 'face',
      'back': '표면',
      ...fields,
    };
    for (final fields in <Map<String, Object?>>[
      {'kind': 'grammar'},
      {'type': 'judgment'},
      {'type': 1},
      {'kind': 'vocabulary', 'senses': <Object>[]},
      {
        'senses': [
          {'pos': '[명]'},
        ],
      },
      {
        'senses': [
          {'pos': 1, 'meaning': '표면'},
        ],
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
              {'pos': null, 'meaning': '표면'},
            ],
          }),
        ],
      }),
    );
    expect((await _extract(valid))!.single.type, CardType.cloze);
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
      (400, 'bad_request'): isA<ServiceFailed>(),
      (500, 'internal'): isA<ServiceFailed>(),
    };
    for (final MapEntry(key: (status, code), value: matcher) in cases.entries) {
      final client = _client((_) async => _json(status, {'error': code}));
      await expectLater(_extract(client), throwsA(matcher), reason: code);
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
