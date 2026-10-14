import 'package:drift/drift.dart';

import '../../deck/deck.dart';
import '../../shared/database.dart';
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

  CardState _toState(CardStateRow row) => CardState(
    stability: row.stability,
    difficulty: row.difficulty,
    lastReview: row.lastReview,
    due: row.due,
  );
}
