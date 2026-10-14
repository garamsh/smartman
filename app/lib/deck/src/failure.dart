import 'model.dart';

/// A failure the deck domain reports to its caller.
sealed class DeckFailure implements Exception {
  const DeckFailure();
}

/// The local database refused or failed an operation.
final class StorageFailure extends DeckFailure {
  const StorageFailure(this.cause);

  final Exception cause;

  @override
  String toString() => 'StorageFailure: $cause';
}

/// A stored card's content could not be decoded.
final class UnreadableCard extends DeckFailure {
  const UnreadableCard(this.cardId, this.cause);

  final CardId cardId;
  final FormatException cause;

  @override
  String toString() => 'UnreadableCard(${cardId.value}): $cause';
}
