import '../../account/account.dart';
import '../../shared/database.dart';

/// A row as the server holds it, with the revision the server stamped on it.
typedef Pulled<R> = ({R row, int revision});

/// The server's copy of the four synced tables, for one signed-in account.
///
/// Every method throws a [SyncFailure] on an expected failure. Rows pass as
/// the local database's row classes; their `dirty` flag is not sent, and a
/// pulled row's is false.
abstract interface class SyncServer {
  /// Up to [limit] of [owner]'s rows of each table with a revision above
  /// [after], lowest revision first. Rows of other accounts the session may
  /// read, such as their public decks, are never pulled.
  Future<List<Pulled<DeckRow>>> pullDecks(UserId owner, int after, int limit);
  Future<List<Pulled<CardRow>>> pullCards(UserId owner, int after, int limit);
  Future<List<Pulled<ReviewRow>>> pullReviews(
    UserId owner,
    int after,
    int limit,
  );
  Future<List<Pulled<CardStateRow>>> pullCardStates(
    UserId owner,
    int after,
    int limit,
  );

  /// Inserts or replaces [rows] as [owner]'s.
  Future<void> pushDecks(UserId owner, List<DeckRow> rows);
  Future<void> pushCards(UserId owner, List<CardRow> rows);
  Future<void> pushCardStates(UserId owner, List<CardStateRow> rows);

  /// Inserts [rows] as [owner]'s. A review the server already holds keeps
  /// every column but its rating and edit time, which take the pushed ones
  /// when the pushed edit time is later.
  Future<void> pushReviews(UserId owner, List<ReviewRow> rows);
}
