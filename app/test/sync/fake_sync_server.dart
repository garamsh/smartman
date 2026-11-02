import 'dart:async';

import 'package:knowno/account/account.dart';
import 'package:knowno/database/database.dart';
import 'package:knowno/sync/sync.dart';

/// A stored row, the account it belongs to, and its revision.
typedef _Stored<R> = ({R row, UserId owner, int revision});

/// Stands in for the Supabase tables at the network boundary, with the rules
/// the server enforces: one revision sequence stamped on every write, rows
/// kept per account, foreign keys between a user's rows that refuse a whole
/// request, and reviews that change only their rating and edit time, and only
/// to a later edit. Its watermark is the sequence's last value; set
/// [purgedBelow] and remove rows to stand in for a purge.
///
/// [account] is the session's account, whose rows a pull returns. Set
/// [failure] to fail every request with it, or [stall] to leave every request
/// unanswered.
class FakeSyncServer implements SyncServer {
  FakeSyncServer(this.account);

  UserId account;
  SyncFailure? failure;
  bool stall = false;

  /// Runs before each push request is answered, with its table's name.
  Future<void> Function(String table)? beforePush;

  /// The horizon [horizon] returns.
  int purgedBelow = 0;

  var _revision = 0;

  /// The last revision stamped.
  int get revision => _revision;
  final decks = <String, _Stored<DeckRow>>{};
  final cards = <String, _Stored<CardRow>>{};
  final reviews = <String, _Stored<ReviewRow>>{};
  final cardStates = <String, _Stored<CardStateRow>>{};

  /// Each account's study settings, as `study_settings` holds them.
  final studySettings = <UserId, StudySettingsRow>{};

  /// Every request the server answered, by method name.
  final requests = <String>[];

  Future<void> _answer(String request) async {
    if (stall) await Completer<void>().future;
    if (failure case final failure?) throw failure;
    requests.add(request);
  }

  @override
  Future<Horizon> horizon() async {
    await _answer('horizon');
    return (horizon: purgedBelow, watermark: _revision);
  }

  List<Pulled<R>> _pull<R>(
    Map<String, _Stored<R>> table,
    UserId owner,
    int after,
    int limit,
    R Function(R) clean,
  ) {
    final rows =
        table.values
            .where((stored) => stored.owner == owner && stored.revision > after)
            .toList()
          ..sort((a, b) => a.revision.compareTo(b.revision));
    return [
      for (final stored in rows.take(limit))
        (row: clean(stored.row), revision: stored.revision),
    ];
  }

  @override
  Future<List<Pulled<DeckRow>>> pullDecks(
    UserId owner,
    int after,
    int limit,
  ) async {
    await _answer('pullDecks');
    _own(owner);
    return _pull(
      decks,
      owner,
      after,
      limit,
      (row) => row.copyWith(dirty: false),
    );
  }

  @override
  Future<List<Pulled<CardRow>>> pullCards(
    UserId owner,
    int after,
    int limit,
  ) async {
    await _answer('pullCards');
    _own(owner);
    return _pull(
      cards,
      owner,
      after,
      limit,
      (row) => row.copyWith(dirty: false),
    );
  }

  @override
  Future<List<Pulled<ReviewRow>>> pullReviews(
    UserId owner,
    int after,
    int limit,
  ) async {
    await _answer('pullReviews');
    _own(owner);
    return _pull(
      reviews,
      owner,
      after,
      limit,
      (row) => row.copyWith(dirty: false),
    );
  }

  @override
  Future<List<Pulled<CardStateRow>>> pullCardStates(
    UserId owner,
    int after,
    int limit,
  ) async {
    await _answer('pullCardStates');
    _own(owner);
    return _pull(
      cardStates,
      owner,
      after,
      limit,
      (row) => row.copyWith(dirty: false),
    );
  }

  void _own(UserId owner) {
    if (owner != account) {
      throw SyncRejected(FormatException('$owner is not the session account'));
    }
  }

  void _parent<R>(Map<String, _Stored<R>> table, String id, UserId owner) {
    if (table[id]?.owner != owner) {
      throw SyncFailed(
        MissingServerParent(FormatException('no parent $id for $owner')),
      );
    }
  }

  _Stored<R> _stamp<R>(R row, UserId owner) =>
      (row: row, owner: owner, revision: ++_revision);

  @override
  Future<void> pushDecks(UserId owner, List<DeckRow> rows) async {
    await beforePush?.call('decks');
    await _answer('pushDecks');
    _own(owner);
    for (final row in rows) {
      decks[row.id] = _stamp(row.copyWith(dirty: false), owner);
    }
  }

  @override
  Future<void> pushCards(UserId owner, List<CardRow> rows) async {
    await beforePush?.call('cards');
    await _answer('pushCards');
    _own(owner);
    for (final row in rows) {
      _parent(decks, row.deckId, owner);
    }
    for (final row in rows) {
      cards[row.id] = _stamp(row.copyWith(dirty: false), owner);
    }
  }

  @override
  Future<void> pushReviews(UserId owner, List<ReviewRow> rows) async {
    await beforePush?.call('reviews');
    await _answer('pushReviews');
    _own(owner);
    for (final row in rows) {
      _parent(cards, row.cardId, owner);
    }
    for (final row in rows) {
      final stored = reviews[row.id];
      if (stored == null) {
        reviews[row.id] = _stamp(row.copyWith(dirty: false), owner);
      } else if (row.updatedAt.isAfter(stored.row.updatedAt)) {
        reviews[row.id] = _stamp(
          stored.row.copyWith(rating: row.rating, updatedAt: row.updatedAt),
          owner,
        );
      }
    }
  }

  @override
  Future<void> pushCardStates(UserId owner, List<CardStateRow> rows) async {
    await beforePush?.call('card_states');
    await _answer('pushCardStates');
    _own(owner);
    for (final row in rows) {
      _parent(cards, row.cardId, owner);
    }
    for (final row in rows) {
      cardStates[row.cardId] = _stamp(row.copyWith(dirty: false), owner);
    }
  }

  @override
  Future<StudySettingsRow?> pullStudySettings(UserId owner) async {
    await _answer('pullStudySettings');
    return studySettings[owner];
  }

  @override
  Future<void> pushStudySettings(UserId owner, StudySettingsRow row) async {
    await beforePush?.call('study_settings');
    await _answer('pushStudySettings');
    _own(owner);
    final stored = studySettings[owner];
    if (stored == null || row.updatedAt.isAfter(stored.updatedAt)) {
      studySettings[owner] = row.copyWith(dirty: false);
    }
  }
}
