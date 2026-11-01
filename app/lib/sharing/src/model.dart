import '../../account/account.dart';
import '../../deck/deck.dart';

/// A public deck as the listing shows it.
final class PublicDeckSummary {
  const PublicDeckSummary({
    required this.id,
    required this.owner,
    required this.ownerName,
    required this.name,
    required this.description,
    required this.cardCount,
    required this.copyCount,
    required this.publishedAt,
  });

  final DeckId id;
  final UserId owner;

  /// The owner's display name; never the owner's email.
  final DisplayName ownerName;
  final String name;
  final String? description;
  final int cardCount;

  /// How many times other users copied the deck.
  final int copyCount;
  final DateTime publishedAt;
}

/// A card of a public deck, read-only.
final class PublicCard {
  const PublicCard({required this.front, required this.back, this.cells});

  final List<Content> front;
  final List<Content> back;

  /// The 칸 a framed card stores, [front] and [back] their projection; null
  /// on a card stored in two sides.
  final List<Cell>? cells;
}

/// The order the listing takes.
enum BrowseSort {
  /// Most recently published first.
  newest,

  /// Most copied first.
  mostCopied,
}

/// Why a user reports a public deck.
enum ReportReason { inappropriate, spam, copyright, other }

/// What a report did.
enum ReportOutcome {
  /// The report was filed.
  reported,

  /// The user had already reported the deck; nothing changed.
  alreadyReported,
}

/// The name shown with a user's public decks: 2 to 20 characters, without
/// surrounding whitespace.
extension type const DisplayName._(String value) {
  /// [input] trimmed, or null when it is not 2 to 20 characters long.
  static DisplayName? tryParse(String input) {
    final trimmed = input.trim();
    final length = trimmed.runes.length;
    return length >= minLength && length <= maxLength
        ? DisplayName._(trimmed)
        : null;
  }

  /// Wraps a name the server returned, which its check already holds to the
  /// same rule.
  const DisplayName.stored(String value) : this._(value);

  static const minLength = 2;
  static const maxLength = 20;
}

/// The longest description a public deck takes, in characters.
const maxDescriptionLength = 300;
