import 'package:drift/drift.dart';

import '../../account/account.dart';
import '../../database/database.dart';
import '../../study/study.dart';
import 'failure.dart';
import 'merge.dart';
import 'server.dart';

/// What applying one pulled page did.
typedef PageApplied = ({
  /// False when a row's parent is not yet on the device, so the page stopped
  /// before it and the cursor stayed below it.
  bool complete,

  /// The cards a pulled review was added to or changed the rating of.
  Set<String> reviewedCards,
});

/// Reads and writes what sync keeps in the local database: the owner, the
/// pull cursors, the dirty flags, and the rows pulls bring.
///
/// A database exception reaches the caller as [SyncFailed].
class SyncStore {
  SyncStore(this._db, this._scheduler, {required this._clock});

  final AppDatabase _db;
  final Scheduler _scheduler;
  final DateTime Function() _clock;

  /// The account the database belongs to; null while none does.
  Future<UserId?> owner() => _guard(() async {
    final row = await _db.select(_db.syncState).getSingleOrNull();
    return row == null ? null : UserId(row.owner);
  });

  /// The pull cursor of each table.
  Future<SyncStateRow> cursors() =>
      _guard(() => _db.select(_db.syncState).getSingle());

  /// Makes [account] the owner. A database another account owns is cleared
  /// first, so none of its rows is pushed; one no account owns keeps its rows,
  /// which were written unsynced and are pushed as [account]'s.
  Future<void> claim(UserId account) => _guard(
    () => _db.transaction(() async {
      final row = await _db.select(_db.syncState).getSingleOrNull();
      if (row?.owner == account.value) return;
      if (row != null) await _deleteAll();
      await _db
          .into(_db.syncState)
          .insert(
            SyncStateCompanion.insert(
              id: const Value(0),
              owner: account.value,
              decksRevision: 0,
              cardsRevision: 0,
              reviewsRevision: 0,
              cardStatesRevision: 0,
            ),
          );
    }),
  );

  /// Deletes every synced row, the owner and the cursors.
  Future<void> clear() => _guard(() => _db.transaction(_deleteAll));

  Future<void> _deleteAll() async {
    await _db.delete(_db.cardStates).go();
    await _db.delete(_db.reviews).go();
    await _db.delete(_db.cards).go();
    await _db.delete(_db.decks).go();
    await _db.delete(_db.syncState).go();
  }

  /// Whether any row is waiting to be pushed.
  Future<bool> hasUnsynced() => _guard(() async {
    for (final table in <ResultSetImplementation<dynamic, dynamic>>[
      _db.decks,
      _db.cards,
      _db.reviews,
      _db.cardStates,
    ]) {
      final query = _db.customSelect(
        'SELECT 1 FROM ${table.entityName} WHERE dirty = 1 LIMIT 1',
        readsFrom: {table},
      );
      if (await query.getSingleOrNull() != null) return true;
    }
    return false;
  });

  Future<PageApplied> applyDecks(List<Pulled<DeckRow>> page) => _apply(
    page,
    local: (row) => (_db.select(
      _db.decks,
    )..where((deck) => deck.id.equals(row.id))).getSingleOrNull(),
    hasParent: (row) async => true,
    merge: mergeDeck,
    take: (row) => _db.into(_db.decks).insertOnConflictUpdate(row),
    keep: (row) =>
        _db.into(_db.decks).insertOnConflictUpdate(row.copyWith(dirty: true)),
    cursor: (revision) => SyncStateCompanion(decksRevision: Value(revision)),
  );

  Future<PageApplied> applyCards(List<Pulled<CardRow>> page) => _apply(
    page,
    local: (row) => (_db.select(
      _db.cards,
    )..where((card) => card.id.equals(row.id))).getSingleOrNull(),
    hasParent: (row) => _exists(_db.decks, row.deckId),
    merge: mergeCard,
    take: (row) => _db.into(_db.cards).insertOnConflictUpdate(row),
    keep: (row) =>
        _db.into(_db.cards).insertOnConflictUpdate(row.copyWith(dirty: true)),
    cursor: (revision) => SyncStateCompanion(cardsRevision: Value(revision)),
  );

  Future<PageApplied> applyReviews(List<Pulled<ReviewRow>> page) => _apply(
    page,
    local: (row) => (_db.select(
      _db.reviews,
    )..where((review) => review.id.equals(row.id))).getSingleOrNull(),
    hasParent: (row) => _exists(_db.cards, row.cardId),
    merge: mergeReview,
    take: (row) => _db.into(_db.reviews).insertOnConflictUpdate(row),
    keep: (row) =>
        _db.into(_db.reviews).insertOnConflictUpdate(row.copyWith(dirty: true)),
    cursor: (revision) => SyncStateCompanion(reviewsRevision: Value(revision)),
    changesCard: (local, remote) =>
        local == null || local.rating != remote.rating ? remote.cardId : null,
  );

  Future<PageApplied> applyCardStates(List<Pulled<CardStateRow>> page) =>
      _apply(
        page,
        local: (row) => (_db.select(
          _db.cardStates,
        )..where((state) => state.cardId.equals(row.cardId))).getSingleOrNull(),
        hasParent: (row) => _exists(_db.cards, row.cardId),
        merge: mergeCardState,
        take: (row) => _db.into(_db.cardStates).insertOnConflictUpdate(row),
        keep: (row) => _db
            .into(_db.cardStates)
            .insertOnConflictUpdate(row.copyWith(dirty: true)),
        cursor: (revision) =>
            SyncStateCompanion(cardStatesRevision: Value(revision)),
      );

  /// Applies [page] in one transaction, in revision order, and moves the
  /// table's cursor to the last row applied. A row whose parent is not on the
  /// device ends the page before it.
  Future<PageApplied> _apply<R>(
    List<Pulled<R>> page, {
    required Future<R?> Function(R row) local,
    required Future<bool> Function(R row) hasParent,
    required Kept Function(R? local, R remote) merge,
    required Future<void> Function(R row) take,
    required Future<void> Function(R row) keep,
    required SyncStateCompanion Function(int revision) cursor,
    String? Function(R? local, R remote)? changesCard,
  }) => _guard(
    () => _db.transaction(() async {
      final reviewed = <String>{};
      int? last;
      var complete = true;
      for (final (:row, :revision) in page) {
        if (!await hasParent(row)) {
          complete = false;
          break;
        }
        final mine = await local(row);
        switch (merge(mine, row)) {
          case Kept.remote:
            await take(row);
            if (changesCard?.call(mine, row) case final card?) {
              reviewed.add(card);
            }
          case Kept.local:
            // A kept local row differs from the server's, so it is pushed.
            await keep(mine as R);
        }
        last = revision;
      }
      if (last != null) await _db.update(_db.syncState).write(cursor(last));
      return (complete: complete, reviewedCards: reviewed);
    }),
  );

  Future<bool> _exists(TableInfo<Table, dynamic> table, String id) async {
    final query = _db.customSelect(
      'SELECT 1 FROM ${table.entityName} WHERE id = ?',
      variables: [Variable.withString(id)],
      readsFrom: {table},
    );
    return await query.getSingleOrNull() != null;
  }

  /// Folds each of [cards]' reviews through the engine from a new card and
  /// stores the state it reaches, unsynced, where it differs from the stored
  /// one.
  Future<void> recompute(Set<String> cards) => _guard(() async {
    for (final card in cards) {
      final reviews =
          await (_db.select(_db.reviews)..where(
                (review) =>
                    review.cardId.equals(card) & review.deletedAt.isNull(),
              ))
              .get();
      final state = await _scheduler.fold(reviews);
      if (state == null) continue;
      await _db.transaction(() async {
        final stored = await (_db.select(
          _db.cardStates,
        )..where((row) => row.cardId.equals(card))).getSingleOrNull();
        if (stored != null &&
            stored.deletedAt == null &&
            stored.stability == state.stability &&
            stored.difficulty == state.difficulty &&
            stored.lastReview.isAtSameMomentAs(state.lastReview) &&
            stored.due.isAtSameMomentAs(state.due)) {
          return;
        }
        await _db
            .into(_db.cardStates)
            .insertOnConflictUpdate(
              CardStateRow(
                cardId: card,
                stability: state.stability,
                difficulty: state.difficulty,
                lastReview: state.lastReview,
                due: state.due,
                updatedAt: _clock(),
                deletedAt: null,
                dirty: true,
              ),
            );
      });
    }
  });

  Future<List<DeckRow>> unsyncedDecks() =>
      _guard(() => (_db.select(_db.decks)..where((row) => row.dirty)).get());

  Future<List<CardRow>> unsyncedCards() =>
      _guard(() => (_db.select(_db.cards)..where((row) => row.dirty)).get());

  Future<List<ReviewRow>> unsyncedReviews() =>
      _guard(() => (_db.select(_db.reviews)..where((row) => row.dirty)).get());

  Future<List<CardStateRow>> unsyncedCardStates() => _guard(
    () => (_db.select(_db.cardStates)..where((row) => row.dirty)).get(),
  );

  /// Clears the dirty flag of each [pushed] deck still as it was pushed; a
  /// deck edited since stays unsynced.
  Future<void> acknowledgeDecks(List<DeckRow> pushed) => _acknowledge(
    pushed,
    current: (row) => (_db.select(
      _db.decks,
    )..where((deck) => deck.id.equals(row.id))).getSingleOrNull(),
    clean: (row) =>
        _db.into(_db.decks).insertOnConflictUpdate(row.copyWith(dirty: false)),
  );

  Future<void> acknowledgeCards(List<CardRow> pushed) => _acknowledge(
    pushed,
    current: (row) => (_db.select(
      _db.cards,
    )..where((card) => card.id.equals(row.id))).getSingleOrNull(),
    clean: (row) =>
        _db.into(_db.cards).insertOnConflictUpdate(row.copyWith(dirty: false)),
  );

  Future<void> acknowledgeReviews(List<ReviewRow> pushed) => _acknowledge(
    pushed,
    current: (row) => (_db.select(
      _db.reviews,
    )..where((review) => review.id.equals(row.id))).getSingleOrNull(),
    clean: (row) => _db
        .into(_db.reviews)
        .insertOnConflictUpdate(row.copyWith(dirty: false)),
  );

  Future<void> acknowledgeCardStates(List<CardStateRow> pushed) => _acknowledge(
    pushed,
    current: (row) => (_db.select(
      _db.cardStates,
    )..where((state) => state.cardId.equals(row.cardId))).getSingleOrNull(),
    clean: (row) => _db
        .into(_db.cardStates)
        .insertOnConflictUpdate(row.copyWith(dirty: false)),
  );

  Future<void> _acknowledge<R>(
    List<R> pushed, {
    required Future<R?> Function(R row) current,
    required Future<void> Function(R row) clean,
  }) => _guard(
    () => _db.transaction(() async {
      for (final row in pushed) {
        if (await current(row) == row) await clean(row);
      }
    }),
  );

  /// Runs [operation], reporting any exception but a [SyncFailure] as
  /// [SyncFailed].
  Future<T> _guard<T>(Future<T> Function() operation) async {
    try {
      return await operation();
    } on SyncFailure {
      rethrow;
    } on Exception catch (cause, stackTrace) {
      Error.throwWithStackTrace(SyncFailed(cause), stackTrace);
    }
  }
}
