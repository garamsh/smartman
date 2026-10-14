import '../../deck/deck.dart';
import 'rust/api/engine.dart';

/// Identifies a stored review.
extension type const ReviewId(String value) {}

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
  });

  final ReviewId id;
  final CardId cardId;
  final Answer answer;
  final DateTime reviewedAt;

  /// How long the card was on screen before the answer.
  final Duration duration;
}
