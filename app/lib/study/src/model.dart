import 'dart:math';

import '../../deck/deck.dart';
import 'rust/api/engine.dart';

/// Identifies a stored review.
extension type const ReviewId(String value) {}

/// The draw, from 0 inclusive to 1 exclusive, that picks where in its fuzz
/// range a review's interval falls. A review keeps its factor, so scheduling
/// it again gives the same due time.
extension type const FuzzFactor._(double value) {
  /// The next draw of [random].
  FuzzFactor.draw(Random random) : this._(random.nextDouble());
}

/// A reviewed card's scheduling state: the engine's memory state and when the
/// card is next due.
final class CardState {
  const CardState({
    required this.stability,
    required this.difficulty,
    required this.lastReview,
    required this.due,
  });

  /// Days until the probability of recall falls to 0.9.
  final double stability;

  /// From 1 to 10.
  final double difficulty;
  final DateTime lastReview;
  final DateTime due;

  @override
  bool operator ==(Object other) =>
      other is CardState &&
      other.stability == stability &&
      other.difficulty == difficulty &&
      other.lastReview.isAtSameMomentAs(lastReview) &&
      other.due.isAtSameMomentAs(due);

  @override
  int get hashCode => Object.hash(
    stability,
    difficulty,
    lastReview.millisecondsSinceEpoch,
    due.millisecondsSinceEpoch,
  );

  @override
  String toString() =>
      'CardState(stability: $stability, difficulty: $difficulty, '
      'lastReview: $lastReview, due: $due)';
}

/// One answer to a card, as stored.
final class Review {
  const Review({
    required this.id,
    required this.cardId,
    required this.answer,
    required this.reviewedAt,
    required this.duration,
    required this.fuzzFactor,
  });

  final ReviewId id;
  final CardId cardId;
  final Answer answer;
  final DateTime reviewedAt;

  /// How long the card was on screen before the answer.
  final Duration duration;

  /// The fuzz factor the review is scheduled with.
  final FuzzFactor fuzzFactor;

  /// This review with its answer changed to [answer], keeping its id, time,
  /// duration and fuzz factor.
  Review withAnswer(Answer answer) => Review(
    id: id,
    cardId: cardId,
    answer: answer,
    reviewedAt: reviewedAt,
    duration: duration,
    fuzzFactor: fuzzFactor,
  );
}

/// The stored rating of [answer], as the `reviews` table constrains it.
String ratingOf(Answer answer) => switch (answer) {
  Answer.know => 'good',
  Answer.dontKnow => 'again',
};

/// The answer a stored [rating] records. The `reviews` table's check admits
/// no other rating, so any other value is a broken invariant.
Answer answerOf(String rating) => switch (rating) {
  'good' => Answer.know,
  'again' => Answer.dontKnow,
  _ => throw StateError('reviews holds the unknown rating $rating'),
};
