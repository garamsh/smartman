import '../../deck/deck.dart';
import 'extraction_client.dart';

/// [cards] with each run of equal card keys combined into its first card,
/// whose back takes each later back by the merge-back rule.
List<CandidateCard> combineDuplicates(List<CandidateCard> cards) {
  final combined = <CardKey, CandidateCard>{};
  for (final card in cards) {
    final key = CardKey.fromFront(card.front);
    final first = combined[key];
    if (first == null) {
      combined[key] = card;
    } else if (mergeBack([TextContent(first.back)], card.back)
        case final back?) {
      combined[key] = CandidateCard(front: first.front, back: plainText(back));
    }
  }
  return combined.values.toList();
}

/// A candidate as the user reviews it.
final class ReviewRow {
  ReviewRow(CandidateCard card) : front = card.front, back = card.back;

  String front;
  String back;
  bool included = true;

  /// What it does if the deck already has its key; skips by default.
  DuplicateChoice choice = DuplicateChoice.skip;

  CardKey get key => CardKey.fromFront(front);
}

/// The rows under review against the keys the deck already holds.
final class Review {
  Review(List<CandidateCard> cards, this.existingKeys)
    : rows = [for (final card in combineDuplicates(cards)) ReviewRow(card)];

  final List<ReviewRow> rows;
  final Set<CardKey> existingKeys;

  bool isDuplicate(ReviewRow row) => existingKeys.contains(row.key);

  /// The rows that will be written: included, and not set to skip.
  Iterable<ReviewRow> get saved => rows.where(
    (row) =>
        row.included &&
        !(isDuplicate(row) && row.choice == DuplicateChoice.skip),
  );

  /// The cards to import. A row that is not a duplicate merges back if a card
  /// with its key appears before it is written, so it is never lost or
  /// doubled.
  List<ImportedCard> toImport() => [
    for (final row in saved)
      ImportedCard(
        front: row.front,
        back: row.back,
        onDuplicate: isDuplicate(row) ? row.choice : DuplicateChoice.mergeBack,
      ),
  ];
}
