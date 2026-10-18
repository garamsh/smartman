import '../../deck/deck.dart';
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
/// photo, combined into one, in the topic of the first.
final class ReviewRow {
  ReviewRow(this.sources) : front = sources.first.front;

  /// Every candidate with this row's key, in the order the photo gave them.
  final List<CandidateCard> sources;

  String front;

  /// The answer the user typed; null while it is the candidates'.
  String? editedBack;

  /// Whether the user removed the row (true) or put it back (false); null
  /// until they do either, when [Review.isRemoved] decides.
  bool? removed;

  String? get topic => sources.first.topic;

  CardKey get key => CardKey.fromFront(front);

  /// The typed answer, or the first candidate's with each later one's
  /// joined by the merge-back rule.
  String get back {
    if (editedBack case final back?) return back;
    var blocks = <Content>[TextContent(sources.first.back)];
    for (final card in sources.skip(1)) {
      blocks = mergeBack(blocks, card.back) ?? blocks;
    }
    return plainText(blocks);
  }
}

/// Whether a row will be written, and if not, why.
enum RowState {
  /// Its topic is on and it is not removed.
  kept,

  /// Removed on its own: by the user, or because the deck holds its key.
  removed,

  /// Its topic is switched off, whatever the row's own state.
  dropped,
}

/// The rows of one topic, which the user keeps or drops as a whole.
final class ReviewTopic {
  ReviewTopic(this.name);

  /// The topic's name; null for the cards of a function that names none.
  final String? name;

  final rows = <ReviewRow>[];

  bool on = true;
}

/// The rows under review, grouped by topic, against the keys the deck they
/// go into already holds.
final class Review {
  Review(List<CandidateCard> cards, this.existingKeys)
    : rows = [for (final group in groupByKey(cards)) ReviewRow(group)] {
    for (final row in rows) {
      var topic = topics.where((topic) => topic.name == row.topic).firstOrNull;
      if (topic == null) {
        topic = ReviewTopic(row.topic);
        topics.add(topic);
      }
      topic.rows.add(row);
    }
  }

  /// Every row of the photo, in the order the photo gave them.
  final List<ReviewRow> rows;

  /// The topics, in the order each first appears.
  final topics = <ReviewTopic>[];

  /// The keys the deck the rows go into holds; replaced when the user
  /// chooses another deck.
  Set<CardKey> existingKeys;

  bool isDuplicate(ReviewRow row) => existingKeys.contains(row.key);

  /// Whether [row] is removed on its own: as the user set it, else when the
  /// deck already holds its key.
  bool isRemoved(ReviewRow row) => row.removed ?? isDuplicate(row);

  ReviewTopic topicOf(ReviewRow row) =>
      topics.firstWhere((topic) => topic.rows.contains(row));

  RowState stateOf(ReviewRow row) => !topicOf(row).on
      ? RowState.dropped
      : isRemoved(row)
      ? RowState.removed
      : RowState.kept;

  /// The rows that will be written.
  Iterable<ReviewRow> get saved =>
      rows.where((row) => stateOf(row) == RowState.kept);

  /// Applies what the user typed for [row], keeping a side left empty as it
  /// was. The row keeps the state it had, so an edit whose front the deck
  /// holds is not removed: it merges back when saved.
  void edit(ReviewRow row, {required String front, required String back}) {
    row.removed = isRemoved(row);
    if (front.trim().isNotEmpty) row.front = front.trim();
    if (back.trim().isNotEmpty && back.trim() != row.back) {
      row.editedBack = back.trim();
    }
  }

  /// The cards to import, each answer as shown. Each merges back into a card
  /// with its key, the deck's or one written before it, so none is doubled.
  List<ImportedCard> toImport() => [
    for (final row in saved)
      ImportedCard(
        front: row.front,
        back: row.back,
        onDuplicate: DuplicateChoice.mergeBack,
      ),
  ];
}
