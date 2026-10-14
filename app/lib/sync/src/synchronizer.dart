import '../../account/account.dart';
import 'failure.dart';
import 'server.dart';
import 'sync_store.dart';

/// One sync run for the signed-in account: claim the database, pull every
/// table and recompute the states of cards whose reviews changed, then push
/// what is unsynced.
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
    await _pull();
    await _push(account);
  }

  Future<void> _pull() async {
    for (var pass = 1; ; pass++) {
      final cursors = await _store.cursors();
      final reviewed = <String>{};
      final complete = [
        await _pullTable(
          cursors.decksRevision,
          _server.pullDecks,
          _store.applyDecks,
          reviewed,
        ),
        await _pullTable(
          cursors.cardsRevision,
          _server.pullCards,
          _store.applyCards,
          reviewed,
        ),
        await _pullTable(
          cursors.reviewsRevision,
          _server.pullReviews,
          _store.applyReviews,
          reviewed,
        ),
        await _pullTable(
          cursors.cardStatesRevision,
          _server.pullCardStates,
          _store.applyCardStates,
          reviewed,
        ),
      ].every((table) => table);
      // After the states are pulled, so a recomputed state replaces a pulled one.
      await _store.recompute(reviewed);
      if (complete) return;
      if (pass == maxPullPasses) throw const SyncFailed(MissingParent());
    }
  }

  /// Pulls one table page by page from [after]; false when a page stopped at
  /// a row whose parent has not arrived.
  Future<bool> _pullTable<R>(
    int after,
    Future<List<Pulled<R>>> Function(int after, int limit) pull,
    Future<PageApplied> Function(List<Pulled<R>> page) apply,
    Set<String> reviewed,
  ) async {
    var cursor = after;
    while (true) {
      final page = await pull(cursor, pageSize);
      final applied = await apply(page);
      reviewed.addAll(applied.reviewedCards);
      if (!applied.complete) return false;
      if (page.length < pageSize) return true;
      cursor = page.last.revision;
    }
  }

  Future<void> _push(UserId account) async {
    await _pushTable(
      account,
      _store.unsyncedDecks,
      _server.pushDecks,
      _store.acknowledgeDecks,
    );
    await _pushTable(
      account,
      _store.unsyncedCards,
      _server.pushCards,
      _store.acknowledgeCards,
    );
    await _pushTable(
      account,
      _store.unsyncedReviews,
      _server.pushReviews,
      _store.acknowledgeReviews,
    );
    await _pushTable(
      account,
      _store.unsyncedCardStates,
      _server.pushCardStates,
      _store.acknowledgeCardStates,
    );
  }

  Future<void> _pushTable<R>(
    UserId account,
    Future<List<R>> Function() unsynced,
    Future<void> Function(UserId owner, List<R> rows) push,
    Future<void> Function(List<R> pushed) acknowledge,
  ) async {
    final rows = await unsynced();
    for (var start = 0; start < rows.length; start += pageSize) {
      final chunk = rows.sublist(
        start,
        start + pageSize < rows.length ? start + pageSize : rows.length,
      );
      await push(account, chunk);
      await acknowledge(chunk);
    }
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
