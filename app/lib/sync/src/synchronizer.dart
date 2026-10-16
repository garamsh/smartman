import '../../account/account.dart';
import 'failure.dart';
import 'server.dart';
import 'sync_store.dart';

/// One sync run for the signed-in account: claim the database, read the
/// horizon, pull every table, rebuilding one the horizon has passed, and
/// recompute the states of cards whose reviews changed, then push what is
/// unsynced and purge the local tombstones.
class Synchronizer {
  Synchronizer(this._store, this._server, {this.pageSize = 500});

  final SyncStore _store;
  final SyncServer _server;

  /// The most rows one pull request asks for, and one push request sends.
  final int pageSize;

  /// How many times a pull starts over when a row arrived before its parent.
  static const maxPullPasses = 3;

  /// Syncs [account]'s rows. Throws a [SyncFailure] when the run stops.
  Future<void> run(UserId account) async {
    await _store.claim(account);
    // Read before the pull starts, so the watermark covers what it returns.
    final horizon = await _server.horizon();
    await _pull(account, horizon);
    await _push(account);
    await _store.purge();
  }

  Future<void> _pull(UserId account, Horizon horizon) async {
    for (var pass = 1; ; pass++) {
      final cursors = await _store.cursors();
      final reviewed = <String>{};
      final complete = [
        await _pullTable(
          SyncedTable.decks,
          cursors.decksRevision,
          horizon,
          (after, limit) => _server.pullDecks(account, after, limit),
          _store.applyDecks,
          (row) => row.id,
          reviewed,
        ),
        await _pullTable(
          SyncedTable.cards,
          cursors.cardsRevision,
          horizon,
          (after, limit) => _server.pullCards(account, after, limit),
          _store.applyCards,
          (row) => row.id,
          reviewed,
        ),
        await _pullTable(
          SyncedTable.reviews,
          cursors.reviewsRevision,
          horizon,
          (after, limit) => _server.pullReviews(account, after, limit),
          _store.applyReviews,
          (row) => row.id,
          reviewed,
        ),
        await _pullTable(
          SyncedTable.cardStates,
          cursors.cardStatesRevision,
          horizon,
          (after, limit) => _server.pullCardStates(account, after, limit),
          _store.applyCardStates,
          (row) => row.cardId,
          reviewed,
        ),
      ].every((table) => table);
      // After the states are pulled, so a recomputed state replaces a pulled one.
      await _store.recompute(reviewed);
      if (complete) return;
      if (pass == maxPullPasses) throw const SyncFailed(MissingParent());
    }
  }

  /// Pulls [table] page by page from [after]; false when a page stopped at a
  /// row whose parent has not arrived.
  ///
  /// A cursor above zero but below the horizon may have passed a purged
  /// tombstone, so the table is rebuilt: pulled from revision 0, then each
  /// synced local row the pull did not return is deleted. A completed pull
  /// raises the cursor to the watermark, so a table no one writes keeps up
  /// with the horizon.
  Future<bool> _pullTable<R>(
    SyncedTable table,
    int after,
    Horizon horizon,
    Future<List<Pulled<R>>> Function(int after, int limit) pull,
    Future<PageApplied> Function(List<Pulled<R>> page) apply,
    String Function(R row) keyOf,
    Set<String> reviewed,
  ) async {
    final rebuild = after > 0 && after < horizon.horizon;
    final pulled = <String>{};
    var cursor = rebuild ? 0 : after;
    while (true) {
      final page = await pull(cursor, pageSize);
      final applied = await apply(page);
      reviewed.addAll(applied.reviewedCards);
      if (!applied.complete) return false;
      if (rebuild) {
        pulled.addAll([for (final (:row, revision: _) in page) keyOf(row)]);
      }
      if (page.length < pageSize) break;
      cursor = page.last.revision;
    }
    if (rebuild) await _store.forgetUnpulled(table, pulled);
    await _store.raiseCursor(table, horizon.watermark);
    return true;
  }

  Future<void> _push(UserId account) async {
    await _pushTable(
      SyncedTable.decks,
      account,
      _store.unsyncedDecks,
      _server.pushDecks,
      _store.acknowledgeDecks,
      (row) => row.id,
    );
    await _pushTable(
      SyncedTable.cards,
      account,
      _store.unsyncedCards,
      _server.pushCards,
      _store.acknowledgeCards,
      (row) => row.id,
    );
    await _pushTable(
      SyncedTable.reviews,
      account,
      _store.unsyncedReviews,
      _server.pushReviews,
      _store.acknowledgeReviews,
      (row) => row.id,
    );
    await _pushTable(
      SyncedTable.cardStates,
      account,
      _store.unsyncedCardStates,
      _server.pushCardStates,
      _store.acknowledgeCardStates,
      (row) => row.cardId,
    );
  }

  Future<void> _pushTable<R>(
    SyncedTable table,
    UserId account,
    Future<List<R>> Function() unsynced,
    Future<void> Function(UserId owner, List<R> rows) push,
    Future<void> Function(List<R> pushed) acknowledge,
    String Function(R row) keyOf,
  ) async {
    final rows = await unsynced();
    for (var start = 0; start < rows.length; start += pageSize) {
      final chunk = rows.sublist(
        start,
        start + pageSize < rows.length ? start + pageSize : rows.length,
      );
      try {
        await push(account, chunk);
      } on SyncFailed catch (failure) {
        if (failure.cause is! MissingServerParent) rethrow;
        await _store.drop(table, [
          for (final row in await _refusedForParent(account, chunk, push))
            keyOf(row),
        ]);
      }
      await acknowledge(chunk);
    }
  }

  /// Pushes [chunk] one row at a time and returns the rows the server refused
  /// for a parent it does not hold. A delete made elsewhere and purged since
  /// wins over them, so the caller deletes them.
  Future<List<R>> _refusedForParent<R>(
    UserId account,
    List<R> chunk,
    Future<void> Function(UserId owner, List<R> rows) push,
  ) async {
    final refused = <R>[];
    for (final row in chunk) {
      try {
        await push(account, [row]);
      } on SyncFailed catch (failure) {
        if (failure.cause is! MissingServerParent) rethrow;
        refused.add(row);
      }
    }
    return refused;
  }
}

/// A pulled row's parent did not arrive within [Synchronizer.maxPullPasses]
/// passes, which the server's foreign keys should rule out.
final class MissingParent implements Exception {
  const MissingParent();

  @override
  String toString() =>
      'MissingParent: a pulled row has no parent on the device';
}
