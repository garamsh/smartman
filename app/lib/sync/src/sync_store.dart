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

/// One of the four synced tables.
enum SyncedTable {
  decks('decks', 'id', 'decks_revision'),
  cards('cards', 'id', 'cards_revision'),
  reviews('reviews', 'id', 'reviews_revision'),
  cardStates('card_states', 'card_id', 'card_states_revision');

  const SyncedTable(this._name, this._key, this._cursor);

  final String _name;

  /// The column a row is identified by.
  final String _key;

  /// The table's pull cursor in `sync_state`.
  final String _cursor;
}

/// The most ids one statement binds.
const _idsPerStatement = 500;

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
    await _db.delete(_db.studySettings).go();
    await _db.delete(_db.mediaUploads).go();
    await _db.delete(_db.mediaDeletions).go();
  }

  /// Whether any row is waiting to be pushed, or any media file waiting to
  /// be uploaded or deleted.
  Future<bool> hasUnsynced() => _guard(() async {
    for (final queue in <ResultSetImplementation<dynamic, dynamic>>[
      _db.mediaUploads,
      _db.mediaDeletions,
    ]) {
      final query = _db.customSelect(
        'SELECT 1 FROM ${queue.entityName} LIMIT 1',
        readsFrom: {queue},
      );
      if (await query.getSingleOrNull() != null) return true;
    }
    for (final table in <ResultSetImplementation<dynamic, dynamic>>[
      _db.decks,
      _db.cards,
      _db.reviews,
      _db.cardStates,
      _db.studySettings,
    ]) {
      final query = _db.customSelect(
        // The term repeats the partial index's, which SQLite needs to use it.
        'SELECT 1 FROM ${table.entityName} WHERE "dirty" LIMIT 1',
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

  /// Moves [table]'s cursor up to [revision], leaving one already above it.
  Future<void> raiseCursor(SyncedTable table, int revision) => _guard(
    () => _db.customUpdate(
      'UPDATE sync_state SET ${table._cursor} = max(${table._cursor}, ?)',
      variables: [Variable.withInt(revision)],
      updates: {_db.syncState},
    ),
  );

  /// Deletes each synced row of [table] whose key is not in [pulled]: the
  /// rows a rebuild found the server no longer holds. An unsynced row stays.
  Future<void> forgetUnpulled(SyncedTable table, Set<String> pulled) => _guard(
    () => _db.transaction(() async {
      final synced = await _db
          .customSelect(
            'SELECT ${table._key} AS k FROM ${table._name} WHERE NOT "dirty"',
            readsFrom: {_tableOf(table)},
          )
          .get();
      await _delete(table, [
        for (final row in synced)
          if (!pulled.contains(row.read<String>('k'))) row.read<String>('k'),
      ]);
    }),
  );

  /// Deletes the rows of [table] keyed by [keys], with what cascades from
  /// them.
  Future<void> drop(SyncedTable table, List<String> keys) =>
      _guard(() => _db.transaction(() => _delete(table, keys)));

  Future<void> _delete(SyncedTable table, List<String> keys) async {
    for (var start = 0; start < keys.length; start += _idsPerStatement) {
      final chunk = keys.skip(start).take(_idsPerStatement).toList();
      await _db.customUpdate(
        'DELETE FROM ${table._name} WHERE ${table._key} IN '
        '(${List.filled(chunk.length, '?').join(', ')})',
        variables: [for (final key in chunk) Variable.withString(key)],
        updates: {_tableOf(table)},
        updateKind: UpdateKind.delete,
      );
    }
  }

  /// Purges the local tombstones once nothing is unsynced: a card or deck
  /// tombstone loses its content in place, a card its sides and key, a deck
  /// its name and description, made private. The rows stay, so a review that arrives later still finds its
  /// card, and nothing cascades to a review. Nothing is marked unsynced, since
  /// the server strips its own copy.
  Future<void> purge() => _guard(
    () => _db.transaction(() async {
      if (await hasUnsynced()) return;
      await _db.customUpdate(
        "UPDATE cards SET front = '[]', back = '[]', card_key = '' "
        "WHERE deleted_at IS NOT NULL "
        "AND (front <> '[]' OR back <> '[]' OR card_key <> '')",
        updates: {_db.cards},
      );
      await _db.customUpdate(
        "UPDATE decks SET name = '', description = NULL, "
        "visibility = 'private' WHERE deleted_at IS NOT NULL "
        "AND (name <> '' OR description IS NOT NULL "
        "OR visibility <> 'private')",
        updates: {_db.decks},
      );
    }),
  );

  TableInfo<Table, dynamic> _tableOf(SyncedTable table) => switch (table) {
    SyncedTable.decks => _db.decks,
    SyncedTable.cards => _db.cards,
    SyncedTable.reviews => _db.reviews,
    SyncedTable.cardStates => _db.cardStates,
  };

  /// Folds each of [cards]' reviews through the engine from a new card and
  /// stores the state it reaches, unsynced, where it differs from the stored
  /// one.
  Future<void> recompute(Set<String> cards) => _guard(() async {
    for (final card in cards) {
      final reviews = await (_db.select(
        _db.reviews,
      )..where((review) => review.cardId.equals(card))).get();
      final state = await _scheduler.fold(reviews);
      if (state == null) continue;
      await _db.transaction(() async {
        final stored = await (_db.select(
          _db.cardStates,
        )..where((row) => row.cardId.equals(card))).getSingleOrNull();
        if (stored != null &&
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

  /// Merges the server's study settings, [pulled], into the device's: the
  /// later edit wins, and a device's copy kept stays unsynced so the next push
  /// repairs the server's. No row on the server leaves the device's as it is.
  Future<void> applyStudySettings(StudySettingsRow? pulled) => _guard(
    () => _db.transaction(() async {
      if (pulled == null) return;
      final local = await _db.select(_db.studySettings).getSingleOrNull();
      switch (mergeStudySettings(local, pulled)) {
        case Kept.remote:
          await _db
              .into(_db.studySettings)
              .insertOnConflictUpdate(pulled.copyWith(dirty: false));
        case Kept.local:
          await _db
              .into(_db.studySettings)
              .insertOnConflictUpdate(local!.copyWith(dirty: true));
      }
    }),
  );

  /// The study settings waiting to be pushed, or null.
  Future<StudySettingsRow?> unsyncedStudySettings() => _guard(
    () => (_db.select(
      _db.studySettings,
    )..where((row) => row.dirty)).getSingleOrNull(),
  );

  /// Clears the study settings' dirty flag while they are still as [pushed];
  /// settings changed since stay unsynced.
  Future<void> acknowledgeStudySettings(StudySettingsRow pushed) =>
      _acknowledge(
        [pushed],
        current: (row) => _db.select(_db.studySettings).getSingleOrNull(),
        clean: (row) => _db
            .into(_db.studySettings)
            .insertOnConflictUpdate(row.copyWith(dirty: false)),
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
