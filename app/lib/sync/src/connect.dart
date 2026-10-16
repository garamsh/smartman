import '../../account/account.dart';
import '../../database/database.dart';
import 'failure.dart';
import 'server.dart';
import 'supabase_sync_server.dart';

/// The server of a build whose configuration cannot sign anyone in. No
/// account is ever signed in there, so no run reaches it; were one to, it is
/// refused.
final class UnavailableSyncServer implements SyncServer {
  const UnavailableSyncServer();

  Never _refuse() => throw const SyncRejected(NoSyncServer());

  @override
  Future<Horizon> horizon() async => _refuse();

  @override
  Future<List<Pulled<DeckRow>>> pullDecks(
    UserId owner,
    int after,
    int limit,
  ) async => _refuse();

  @override
  Future<List<Pulled<CardRow>>> pullCards(
    UserId owner,
    int after,
    int limit,
  ) async => _refuse();

  @override
  Future<List<Pulled<ReviewRow>>> pullReviews(
    UserId owner,
    int after,
    int limit,
  ) async => _refuse();

  @override
  Future<List<Pulled<CardStateRow>>> pullCardStates(
    UserId owner,
    int after,
    int limit,
  ) async => _refuse();

  @override
  Future<void> pushDecks(UserId owner, List<DeckRow> rows) async => _refuse();

  @override
  Future<void> pushCards(UserId owner, List<CardRow> rows) async => _refuse();

  @override
  Future<void> pushReviews(UserId owner, List<ReviewRow> rows) async =>
      _refuse();

  @override
  Future<void> pushCardStates(UserId owner, List<CardStateRow> rows) async =>
      _refuse();
}

/// The build has no server to sync with.
final class NoSyncServer implements Exception {
  const NoSyncServer();

  @override
  String toString() => 'NoSyncServer: this build cannot sign in';
}

/// The server sync reaches through [connection]'s client, or one refusing
/// every request when the build cannot sign in.
SyncServer connectSyncServer(AccountConnection connection) =>
    switch (connection.client) {
      final client? => SupabaseSyncServer(client),
      null => const UnavailableSyncServer(),
    };
