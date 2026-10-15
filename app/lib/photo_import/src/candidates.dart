import '../../deck/deck.dart';
import 'detail_level.dart';
import 'extraction_client.dart';

/// [cards] grouped by card key, in the order each key first appears.
List<List<CandidateCard>> groupByKey(List<CandidateCard> cards) {
  final groups = <CardKey, List<CandidateCard>>{};
  for (final card in cards) {
    (groups[CardKey.fromFront(card.front)] ??= []).add(card);
  }
  return groups.values.toList();
}

/// A candidate as the user reviews it: the candidates of one card key on the
/// photo, combined into one.
final class ReviewRow {
  ReviewRow(this.sources) : front = sources.first.front;

  /// Every candidate with this row's key, in the order the photo gave them.
  final List<CandidateCard> sources;

  String front;

  /// The answer the user typed, which no level switch replaces; null while
  /// the answer follows the level.
  String? editedBack;

  bool included = true;

  /// What it does if the deck already has its key; skips by default.
  DuplicateChoice choice = DuplicateChoice.skip;

  CardKey get key => CardKey.fromFront(front);

  bool get edited => editedBack != null;

  /// The answer at [level]: the typed one, or the first candidate's
  /// answer with each later one's joined by the merge-back rule.
  String backAt(DetailLevel level) {
    if (editedBack case final back?) return back;
    var blocks = <Content>[TextContent(sources.first.backAt(level))];
    for (final card in sources.skip(1)) {
      blocks = mergeBack(blocks, card.backAt(level)) ?? blocks;
    }
    return plainText(blocks);
  }
}

/// The rows under review at a detail level, against the keys the deck
/// already holds.
final class Review {
  Review(List<CandidateCard> cards, this.existingKeys, {required this.level})
    : rows = [for (final group in groupByKey(cards)) ReviewRow(group)];

  final List<ReviewRow> rows;
  final Set<CardKey> existingKeys;

  /// How much each answer says; switching it recomposes every answer the
  /// user did not type.
  DetailLevel level;

  bool isDuplicate(ReviewRow row) => existingKeys.contains(row.key);

  /// The rows that will be written: included, and not set to skip.
  Iterable<ReviewRow> get saved => rows.where(
    (row) =>
        row.included &&
        !(isDuplicate(row) && row.choice == DuplicateChoice.skip),
  );

  /// The cards to import, each answer as shown. A row that is not a
  /// duplicate merges back if a card with its key appears before it is
  /// written, so it is never lost or doubled.
  List<ImportedCard> toImport() => [
    for (final row in saved)
      ImportedCard(
        front: row.front,
        back: row.backAt(level),
        onDuplicate: isDuplicate(row) ? row.choice : DuplicateChoice.mergeBack,
      ),
  ];
}
