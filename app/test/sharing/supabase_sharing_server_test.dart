import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:smartman/deck/deck.dart';
import 'package:smartman/sharing/sharing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  test(
    'a publish sends every time in UTC, truncated to the millisecond',
    () async {
      final sent = <Map<String, dynamic>>[];
      final client = SupabaseClient(
        'https://example.test',
        'anon-key',
        httpClient: MockClient((request) async {
          sent.add(jsonDecode(request.body) as Map<String, dynamic>);
          return http.Response('', 201, request: request);
        }),
      );
      addTearDown(client.dispose);
      // Times with sub-millisecond parts in a zone other than UTC, as
      // DateTime.now() gives them.
      final created = DateTime.utc(2026, 10, 1, 9, 30, 0, 123, 456).toLocal();
      final at = DateTime.utc(2026, 10, 17, 12, 0, 5, 789, 321).toLocal();
      expect(created.microsecond, 456);
      expect(at.microsecond, 321);
      final deck = Deck(
        id: const DeckId('0199f3b2-7c1e-7a00-8000-000000000001'),
        name: 'Verbs',
        createdAt: created,
        updatedAt: created,
      );

      await SupabaseSharingServer(client)
          .writeVisibility(deck, PublicDeck(at), description: 'about', at: at);

      expect(sent, hasLength(1));
      expect(
        sent.single,
        containsPair('created_at', '2026-10-01T09:30:00.123Z'),
      );
      expect(
        sent.single,
        containsPair('updated_at', '2026-10-17T12:00:05.789Z'),
      );
      expect(
        sent.single,
        containsPair('published_at', '2026-10-17T12:00:05.789Z'),
      );
    },
  );

  test('a card is read from its 칸 list when free v2 and from its sides '
      'otherwise', () async {
    final asked = <Uri>[];
    final client = SupabaseClient(
      'https://example.test',
      'anon-key',
      httpClient: MockClient((request) async {
        asked.add(request.url);
        return http.Response(
          jsonEncode([
            {
              'front': [
                {
                  'type': 'text',
                  'v': 2,
                  'id': 'a',
                  'payload': {'front': 'one', 'back': 'two'},
                },
              ],
              'back': <Object>[],
              'template': 'free',
              'template_version': 2,
            },
            {
              'front': [
                {
                  'type': 'text',
                  'v': 1,
                  'payload': {'text': 'three'},
                },
              ],
              'back': [
                {
                  'type': 'text',
                  'v': 1,
                  'payload': {'text': 'four'},
                },
              ],
              'template': null,
              'template_version': null,
            },
          ]),
          200,
          request: request,
          headers: {'content-type': 'application/json'},
        );
      }),
    );
    addTearDown(client.dispose);

    final [framed, earlier] = await SupabaseSharingServer(client)
        .listCards(const DeckId('deck'), limit: 2);

    expect(
      asked.single.queryParameters['select'],
      contains('template_version'),
    );
    expect(framed.cells, const [TextCell(front: 'one', back: 'two')]);
    expect(framed.front, const [TextContent('one')]);
    expect(framed.back, const [TextContent('two')]);
    expect(earlier.cells, isNull);
    expect(earlier.front, const [TextContent('three')]);
    expect(earlier.back, const [TextContent('four')]);
  });
}
