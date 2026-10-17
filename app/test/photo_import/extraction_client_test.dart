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

  test(
    'a card from a function before kind takes its meaning as its answer and '
    'short form, as vocabulary at step 1, with its part of speech and examples',
    () async {
      final client = _client(
        (_) async => _json(200, {
          'cards': [
            {
              'front': 'run',
              'back': '[동] 달리다',
              'meaning': ' 달리다 ',
              'partOfSpeech': '[동]',
              'examples': ['I run every morning.', ' run a shop '],
            },
            {'front': 'river', 'back': '강', 'meaning': '강'},
          ],
        }),
      );

      final [run, river] = (await _extract(client))!;

      expect(
        (run.front, run.answer, run.short, run.partOfSpeech),
        ('run', '달리다', '달리다', '[동]'),
      );
      expect(run.examples, ['I run every morning.', 'run a shop']);
      expect((river.answer, river.partOfSpeech), ('강', null));
      expect(river.examples, isEmpty);
      for (final card in [run, river]) {
        expect(
          (card.kind, card.step),
          (CandidateKind.vocabulary, DetailStep.core),
        );
      }
    },
  );

  test(
    'a card from a function that sends back alone takes back as its answer',
    () async {
      final client = _client(
        (_) async => _json(200, {
          'cards': [
            {'front': 'chat', 'back': 'n. cat'},
          ],
        }),
      );

      final [card] = (await _extract(client))!;

      expect(
        (card.answer, card.short, card.partOfSpeech),
        ('n. cat', 'n. cat', null),
      );
      expect(
        (card.kind, card.step),
        (CandidateKind.vocabulary, DetailStep.core),
      );
      expect(card.examples, isEmpty);
    },
  );

  test('a card with kind reads its kind, answer, short form and step, and a '
      'vocabulary card its part of speech and examples', () async {
    final client = _client(
      (_) async => _json(200, {
        'cards': [
          {
            'kind': 'vocabulary',
            'front': 'run',
            'answer': ' 달리다, 운영하다 ',
            'short': '달리다',
            'step': 1,
            'back': '[동] 달리다, 운영하다',
            'meaning': '달리다, 운영하다',
            'partOfSpeech': '[동]',
            'examples': ['I run every morning.'],
          },
          {
            'kind': 'note',
            'front': '연역 논증이란?',
            'answer': '전제가 참이면 결론이 반드시 참인 논증',
            'short': '결론이 반드시 참',
            'step': 4,
            'back': '전제가 참이면 결론이 반드시 참인 논증',
            'examples': ['253+4637+647898=652788 -> 연역'],
          },
        ],
      }),
    );

    final [run, deduction] = (await _extract(client))!;

    expect(
      (run.kind, run.answer, run.short, run.step, run.partOfSpeech),
      (CandidateKind.vocabulary, '달리다, 운영하다', '달리다', DetailStep.core, '[동]'),
    );
    expect(run.examples, ['I run every morning.']);
    expect(
      (
        deduction.kind,
        deduction.front,
        deduction.answer,
        deduction.short,
        deduction.step,
        deduction.partOfSpeech,
      ),
      (
        CandidateKind.note,
        '연역 논증이란?',
        '전제가 참이면 결론이 반드시 참인 논증',
        '결론이 반드시 참',
        DetailStep.detailed,
        null,
      ),
    );
    expect(deduction.examples, ['253+4637+647898=652788 -> 연역']);
  });

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
        'meaning': ' ',
        'partOfSpeech': 1,
        'examples': 'a cat',
      }.entries)
        jsonEncode({
          'cards': [
            {'front': 'chat', 'back': 'cat', field.key: field.value},
          ],
        }),
      jsonEncode({
        'cards': [
          {
            'front': 'chat',
            'back': 'cat',
            'examples': ['a cat', ''],
          },
        ],
      }),
      for (final field in <String, Object?>{
        'kind': 'word',
        'answer': ' ',
        'short': null,
        'step': 6,
      }.entries)
        jsonEncode({
          'cards': [
            {
              'kind': 'note',
              'front': 'What is an argument?',
              'answer': 'Premises and a conclusion',
              'short': 'Premises',
              'step': 2,
              'back': 'Premises and a conclusion',
              field.key: field.value,
            },
          ],
        }),
      jsonEncode({
        'cards': [
          {
            'kind': 'note',
            'front': 'What is an argument?',
            'answer': 'Premises and a conclusion',
            'short': 'Premises',
            'step': 0,
            'back': 'Premises and a conclusion',
          },
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
