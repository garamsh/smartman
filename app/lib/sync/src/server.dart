import '../../account/account.dart';
import '../../database/database.dart';
import 'failure.dart';

/// A row as the server holds it, with the revision the server stamped on it.
typedef Pulled<R> = ({R row, int revision});

/// What a run reads from the server before it pulls.
typedef Horizon = ({
  /// The revision at or below which tombstones may have been purged; 0 until
  /// a purge has run.
  int horizon,

  /// A revision no row of the session's account at or below which is still
  /// uncommitted, so a pull started after reading it and completed has
  /// returned every such row.
  int watermark,
});

/// The server's copy of the four synced tables, for one signed-in account.
///
/// Every method throws a [SyncFailure] on an expected failure. Rows pass as
/// the local database's row classes; their `dirty` flag is not sent, and a
/// pulled row's is false.
abstract interface class SyncServer {
  /// The signed-in account's horizon and watermark.
  Future<Horizon> horizon();

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

  /// Inserts or replaces [rows] as [owner]'s. A row whose parent the server
  /// does not hold is refused as [SyncFailed] with [MissingServerParent], and
  /// the request changes nothing.
  Future<void> pushDecks(UserId owner, List<DeckRow> rows);
  Future<void> pushCards(UserId owner, List<CardRow> rows);
  Future<void> pushCardStates(UserId owner, List<CardStateRow> rows);

  /// [owner]'s study settings, or null while [owner] has set none.
  Future<StudySettingsRow?> pullStudySettings(UserId owner);

  /// Stores [row] as [owner]'s study settings where the server's are older or
  /// absent; the later edit wins, as a review's rating does.
  Future<void> pushStudySettings(UserId owner, StudySettingsRow row);

  /// Inserts [rows] as [owner]'s. A review the server already holds keeps
  /// every column but its rating and edit time, which take the pushed ones
  /// when the pushed edit time is later. A review whose card the server does
  /// not hold is refused as the other pushes refuse such a row.
  Future<void> pushReviews(UserId owner, List<ReviewRow> rows);
}
