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
}
