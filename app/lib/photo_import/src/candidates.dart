import '../../deck/deck.dart';
import 'detail_step.dart';
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

  /// The answer the user typed, which no step change replaces; null while
  /// the answer follows the step.
  String? editedBack;

  bool included = true;

  /// What it does if the deck already has its key; skips by default.
  DuplicateChoice choice = DuplicateChoice.skip;

  CardKey get key => CardKey.fromFront(front);

  bool get edited => editedBack != null;

  /// Whether the row is offered at [step]: one of its candidates is.
  bool offeredAt(DetailStep step) =>
      sources.any((card) => card.offeredAt(step));

  /// The answer at [step]: the typed one, or the answer of the first
  /// candidate offered at [step] with each later one's joined by the
  /// merge-back rule.
  String backAt(DetailStep step) {
    if (editedBack case final back?) return back;
    final offered = [
      for (final card in sources)
        if (card.offeredAt(step)) card,
    ];
    if (offered.isEmpty) return '';
    var blocks = <Content>[TextContent(offered.first.backAt(step))];
    for (final card in offered.skip(1)) {
      blocks = mergeBack(blocks, card.backAt(step)) ?? blocks;
    }
    return plainText(blocks);
  }
}

/// The rows under review at a detail step, against the keys the deck already
/// holds.
final class Review {
  Review(List<CandidateCard> cards, this.existingKeys, {required this.step})
    : rows = [for (final group in groupByKey(cards)) ReviewRow(group)];

  /// Every row of the photo, offered or not, each keeping its edits, its
  /// checkbox and its duplicate option while a step hides it.
  final List<ReviewRow> rows;
  final Set<CardKey> existingKeys;

  /// Which rows are offered and how much each answer says; changing it
  /// recomposes every answer the user did not type.
  DetailStep step;

  /// The rows offered at [step], in the photo's order.
  Iterable<ReviewRow> get offered => rows.where((row) => row.offeredAt(step));

  bool isDuplicate(ReviewRow row) => existingKeys.contains(row.key);

  /// The rows that will be written: offered, included, and not set to skip.
  Iterable<ReviewRow> get saved => offered.where(
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
        back: row.backAt(step),
        onDuplicate: isDuplicate(row) ? row.choice : DuplicateChoice.mergeBack,
      ),
  ];
}
