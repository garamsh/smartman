import 'dart:async';
import 'dart:convert';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../../account/account.dart';
import '../../shared/database.dart';
import 'failure.dart';
import 'server.dart';

/// The server's tables, reached through PostgREST with the session the
/// `account` domain signed in, whose row-level security limits every request
/// to the session's own rows.
final class SupabaseSyncServer implements SyncServer {
  SupabaseSyncServer(
    this._client, {
    this.timeout = const Duration(seconds: 20),
  });

  final SupabaseClient _client;

  /// How long one request may take before it counts as offline.
  final Duration timeout;

  @override
  Future<List<Pulled<DeckRow>>> pullDecks(int after, int limit) =>
      _pull('decks', after, limit, _decodeDeck);

  @override
  Future<List<Pulled<CardRow>>> pullCards(int after, int limit) =>
      _pull('cards', after, limit, _decodeCard);

  @override
  Future<List<Pulled<ReviewRow>>> pullReviews(int after, int limit) =>
      _pull('reviews', after, limit, _decodeReview);

  @override
  Future<List<Pulled<CardStateRow>>> pullCardStates(int after, int limit) =>
      _pull('card_states', after, limit, _decodeCardState);

  Future<List<Pulled<R>>> _pull<R>(
    String table,
    int after,
    int limit,
    R Function(_Fields fields) decode,
  ) => _request(() async {
    final rows = await _client
        .from(table)
        .select()
        .gt('revision', after)
        .order('revision', ascending: true)
        .limit(limit);
    return [
      for (final row in rows)
        (row: decode(_Fields(row)), revision: _Fields(row).integer('revision')),
    ];
  });

  @override
  Future<void> pushDecks(UserId owner, List<DeckRow> rows) => _request(
    () => _client.from('decks').upsert([
      for (final row in rows)
        {
          'id': row.id,
          'user_id': owner.value,
          'name': row.name,
          'created_at': _time(row.createdAt),
          'updated_at': _time(row.updatedAt),
          'deleted_at': _timeOrNull(row.deletedAt),
        },
    ]),
  );

  @override
  Future<void> pushCards(UserId owner, List<CardRow> rows) => _request(
    () => _client.from('cards').upsert([
      for (final row in rows)
        {
          'id': row.id,
          'user_id': owner.value,
          'deck_id': row.deckId,
          'front': jsonDecode(row.front),
          'back': jsonDecode(row.back),
          'card_key': row.cardKey,
          'source': row.source,
          'created_at': _time(row.createdAt),
          'updated_at': _time(row.updatedAt),
          'deleted_at': _timeOrNull(row.deletedAt),
        },
    ]),
  );

  @override
  Future<void> pushCardStates(UserId owner, List<CardStateRow> rows) =>
      _request(
        () => _client.from('card_states').upsert([
          for (final row in rows)
            {
              'user_id': owner.value,
              'card_id': row.cardId,
              'stability': row.stability,
              'difficulty': row.difficulty,
              'last_review': _time(row.lastReview),
              'due': _time(row.due),
              'updated_at': _time(row.updatedAt),
              'deleted_at': _timeOrNull(row.deletedAt),
            },
        ], onConflict: 'user_id,card_id'),
      );

  /// Inserts the reviews the server lacks, then moves each other review's
  /// rating to the pushed one where the server's edit is older. A client may
  /// update no other column of a review.
  @override
  Future<void> pushReviews(
    UserId owner,
    List<ReviewRow> rows,
  ) => _request(() async {
    final inserted = await _client
        .from('reviews')
        .upsert([
          for (final row in rows)
            {
              'id': row.id,
              'user_id': owner.value,
              'card_id': row.cardId,
              'rating': row.rating,
              'reviewed_at': _time(row.reviewedAt),
              'duration_ms': row.durationMs,
              'fuzz_factor': row.fuzzFactor,
              'updated_at': _time(row.updatedAt),
            },
        ], ignoreDuplicates: true)
        .select('id');
    final insertedIds = {for (final row in inserted) _Fields(row).string('id')};
    for (final row in rows) {
      if (insertedIds.contains(row.id)) continue;
      await _client
          .from('reviews')
          .update({'rating': row.rating, 'updated_at': _time(row.updatedAt)})
          .eq('id', row.id)
          .lt('updated_at', _time(row.updatedAt));
    }
  });

  /// Runs [request] within [timeout], mapping each expected failure to its
  /// [SyncFailure].
  Future<T> _request<T>(Future<T> Function() request) async {
    try {
      return await request().timeout(timeout);
    } on TimeoutException catch (cause) {
      throw SyncOffline(cause);
    } on PostgrestException catch (cause) {
      throw classifyPostgrestError(cause);
    } on AuthException catch (cause) {
      throw SyncRejected(cause);
    } on FormatException catch (cause) {
      throw SyncFailed(cause);
    } on Exception catch (cause) {
      // The HTTP client's own failures: no connection, a dropped request.
      throw SyncOffline(cause);
    }
  }
}

/// The failure a PostgREST [error] means. Its code is Postgres's, PostgREST's
/// own (`PGRST…`), or the HTTP status when the body carried neither.
SyncFailure classifyPostgrestError(PostgrestException error) =>
    switch (error.code) {
      // A refused privilege or row-level security policy, or a session
      // PostgREST no longer accepts.
      '42501' ||
      'PGRST301' ||
      'PGRST302' ||
      '401' ||
      '403' => SyncRejected(error),
      // PostgREST could not reach the database, or the gateway the server.
      'PGRST000' ||
      'PGRST001' ||
      'PGRST002' ||
      '500' ||
      '502' ||
      '503' ||
      '504' => SyncOffline(error),
      _ => SyncFailed(error),
    };

String _time(DateTime time) => time.toUtc().toIso8601String();

String? _timeOrNull(DateTime? time) => time == null ? null : _time(time);

DeckRow _decodeDeck(_Fields row) => DeckRow(
  id: row.string('id'),
  name: row.string('name'),
  createdAt: row.time('created_at'),
  updatedAt: row.time('updated_at'),
  deletedAt: row.timeOrNull('deleted_at'),
  dirty: false,
);

CardRow _decodeCard(_Fields row) => CardRow(
  id: row.string('id'),
  deckId: row.string('deck_id'),
  front: row.json('front'),
  back: row.json('back'),
  cardKey: row.string('card_key'),
  source: row.string('source'),
  createdAt: row.time('created_at'),
  updatedAt: row.time('updated_at'),
  deletedAt: row.timeOrNull('deleted_at'),
  dirty: false,
);

ReviewRow _decodeReview(_Fields row) => ReviewRow(
  id: row.string('id'),
  cardId: row.string('card_id'),
  rating: row.string('rating'),
  reviewedAt: row.time('reviewed_at'),
  durationMs: row.integer('duration_ms'),
  fuzzFactor: row.numberOrNull('fuzz_factor'),
  updatedAt: row.time('updated_at'),
  deletedAt: row.timeOrNull('deleted_at'),
  dirty: false,
);

CardStateRow _decodeCardState(_Fields row) => CardStateRow(
  cardId: row.string('card_id'),
  stability: row.number('stability'),
  difficulty: row.number('difficulty'),
  lastReview: row.time('last_review'),
  due: row.time('due'),
  updatedAt: row.time('updated_at'),
  deletedAt: row.timeOrNull('deleted_at'),
  dirty: false,
);

/// A row PostgREST returned, read field by field; a field of the wrong type
/// throws [FormatException].
extension type _Fields(Map<String, dynamic> row) {
  T _read<T>(String key) => switch (row[key]) {
    final T value => value,
    final other => throw FormatException(
      'expected $key to be $T, found ${other.runtimeType}',
    ),
  };

  String string(String key) => _read<String>(key);

  int integer(String key) => _read<int>(key);

  double number(String key) => _read<num>(key).toDouble();

  double? numberOrNull(String key) => _read<num?>(key)?.toDouble();

  DateTime time(String key) => DateTime.parse(string(key));

  DateTime? timeOrNull(String key) => switch (_read<String?>(key)) {
    final String value => DateTime.parse(value),
    null => null,
  };

  /// A `jsonb` value, encoded as the local database stores it.
  String json(String key) => jsonEncode(_read<List<dynamic>>(key));
}
