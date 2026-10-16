import 'package:drift/drift.dart';

import '../../database/database.dart';
import '../../deck/deck.dart';
import 'failure.dart';
import 'model.dart';

/// Reads and writes the study domain's tables: card states and reviews.
///
/// A failed read reaches the caller as [StudyStorageFailure], and a failed
/// write as [AnswerNotSaved].
class StudyRepository {
  StudyRepository(this._db, {required this._newId});

  final AppDatabase _db;
  final String Function() _newId;

  /// A fresh id for a review about to be recorded.
  ReviewId newReviewId() => ReviewId(_newId());

  /// The stored state of each of [cards] that has one; a card never reviewed
  /// is absent.
  Future<Map<CardId, CardState>> statesOf(List<CardId> cards) async {
    try {
      final query = _db.select(_db.cardStates)
        ..where(
          (row) =>
              row.cardId.isIn([for (final card in cards) card.value]) &
              row.deletedAt.isNull(),
        );
      return {
        for (final row in await query.get()) CardId(row.cardId): _toState(row),
      };
    } on Exception catch (cause, stackTrace) {
      Error.throwWithStackTrace(StudyStorageFailure(cause), stackTrace);
    }
  }

  /// Stores [reviews] of [card] and the card's [state] after the last of
  /// them, in one transaction, each row edited [at] and left for sync to
  /// push. A review already stored under the same id is replaced, which is how
  /// a toggled answer is rewritten.
  Future<void> record(
    CardId card,
    List<Review> reviews,
    CardState state, {
    required DateTime at,
  }) async {
    try {
      await _db.transaction(() async {
        for (final review in reviews) {
          await _db
              .into(_db.reviews)
              .insertOnConflictUpdate(
                ReviewRow(
                  id: review.id.value,
                  cardId: review.cardId.value,
                  rating: ratingOf(review.answer),
                  reviewedAt: review.reviewedAt,
                  durationMs: review.duration.inMilliseconds,
                  fuzzFactor: review.fuzzFactor.value,
                  updatedAt: at,
                  dirty: true,
                ),
              );
        }
        await _db
            .into(_db.cardStates)
            .insertOnConflictUpdate(
              CardStateRow(
                cardId: card.value,
                stability: state.stability,
                difficulty: state.difficulty,
                lastReview: state.lastReview,
                due: state.due,
                updatedAt: at,
                dirty: true,
              ),
            );
      });
    } on Exception catch (cause, stackTrace) {
      Error.throwWithStackTrace(AnswerNotSaved(cause), stackTrace);
    }
  }

  // The reads by time below are written in SQL: drift compares text times
  // through julianday(), which no index on reviewed_at serves. Each repeats
  // the partial index's term, `deleted_at IS NULL`, so SQLite can use it.

  /// When the user first answered each card whose first answer, not
  /// deleted, is at or after [since], across every deck. Only the cards
  /// answered since then are grouped.
  Future<List<DateTime>> firstAnswersSince(DateTime since) => _read(() async {
    final rows = await _db
        .customSelect(
          'SELECT min(reviewed_at) AS first FROM reviews '
          'WHERE deleted_at IS NULL AND card_id IN ('
          'SELECT card_id FROM reviews '
          'WHERE deleted_at IS NULL AND reviewed_at >= ?1) '
          'GROUP BY card_id HAVING min(reviewed_at) >= ?1',
          variables: [Variable<DateTime>(storedTime(since))],
          readsFrom: {_db.reviews},
        )
        .get();
    return [for (final row in rows) row.read<DateTime>('first')];
  });

  /// Every answer not deleted given at or after [since], oldest first.
  Future<List<StoredAnswer>> answersSince(DateTime since) => _read(() async {
    final rows = await _db
        .customSelect(
          'SELECT * FROM reviews WHERE deleted_at IS NULL AND reviewed_at >= ? '
          'ORDER BY reviewed_at',
          variables: [Variable<DateTime>(storedTime(since))],
          readsFrom: {_db.reviews},
        )
        .map((row) => _db.reviews.map(row.data))
        .get();
    return [
      for (final row in rows)
        (
          card: CardId(row.cardId),
          answer: answerOf(row.rating),
          at: row.reviewedAt,
          duration: Duration(milliseconds: row.durationMs),
        ),
    ];
  });

  /// The time of the latest answer not deleted given before [end], or null
  /// when there is none: one probe of the index on `reviewed_at`.
  Future<DateTime?> latestAnswerBefore(DateTime end) => _read(() async {
    final row = await _db
        .customSelect(
          'SELECT max(reviewed_at) AS latest FROM reviews '
          'WHERE deleted_at IS NULL AND reviewed_at < ?',
          variables: [Variable<DateTime>(storedTime(end))],
          readsFrom: {_db.reviews},
        )
        .getSingle();
    return row.readNullable<DateTime>('latest');
  });

  Future<T> _read<T>(Future<T> Function() read) async {
    try {
      return await read();
    } on Exception catch (cause, stackTrace) {
      Error.throwWithStackTrace(StudyStorageFailure(cause), stackTrace);
    }
  }

  /// The median time the user took over their last [paceWindow] reviews, or
  /// null while they have fewer than [paceMinimum].
  Future<Duration?> medianReviewDuration() async {
    try {
      final query = _db.selectOnly(_db.reviews)
        ..addColumns([_db.reviews.durationMs])
        ..where(_db.reviews.deletedAt.isNull())
        ..orderBy([OrderingTerm.desc(_db.reviews.reviewedAt)])
        ..limit(paceWindow);
      final durations = [
        for (final row in await query.get()) row.read(_db.reviews.durationMs)!,
      ]..sort();
      if (durations.length < paceMinimum) return null;
      final middle = durations.length ~/ 2;
      final median = durations.length.isOdd
          ? durations[middle]
          : (durations[middle - 1] + durations[middle]) ~/ 2;
      return Duration(milliseconds: median);
    } on Exception catch (cause, stackTrace) {
      Error.throwWithStackTrace(StudyStorageFailure(cause), stackTrace);
    }
  }

  /// How many of the latest reviews the pace is the median of.
  static const paceWindow = 200;

  /// The fewest reviews a pace is read from.
  static const paceMinimum = 20;

  CardState _toState(CardStateRow row) => CardState(
    stability: row.stability,
    difficulty: row.difficulty,
    lastReview: row.lastReview,
    due: row.due,
  );
}
