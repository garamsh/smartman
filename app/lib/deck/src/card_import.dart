import 'card_key.dart';
import 'content.dart';
import 'model.dart';

/// The deck an import saves into.
sealed class ImportTarget {
  const ImportTarget();
}

/// An existing deck.
final class ImportIntoDeck extends ImportTarget {
  const ImportIntoDeck(this.deck);

  final DeckId deck;
}

/// A deck the import creates, named [name].
final class ImportIntoNewDeck extends ImportTarget {
  const ImportIntoNewDeck(this.name);

  final String name;
}

/// Where imported cards come from, which their stored source records.
sealed class ImportSource {
  const ImportSource();
}

/// Cards read off a photo, stored as [CardSource.import].
final class FromPhoto extends ImportSource {
  const FromPhoto();
}

/// Cards copied from another user's public deck [origin], stored as
/// [CardSource.shared] with that origin.
final class FromPublicDeck extends ImportSource {
  const FromPublicDeck(this.origin);

  final DeckId origin;
}

/// What an imported card does when a card in its deck already has its key.
enum DuplicateChoice {
  /// Writes nothing.
  skip,

  /// Appends the imported back to the existing card's back on a new line,
  /// unless a line of that back already holds it.
  mergeBack,

  /// Adds the imported card beside the existing one.
  addNew,
}

/// A card to import, its sides as content blocks, and what it does when its
/// key collides.
final class ImportedCard {
  const ImportedCard({
    required this.front,
    required this.back,
    required this.onDuplicate,
  });

  final List<Content> front;
  final List<Content> back;
  final DuplicateChoice onDuplicate;
}

/// What an import wrote into [deck]: [added] new cards and [merged] backs.
final class CardsImported {
  const CardsImported({
    required this.deck,
    required this.added,
    required this.merged,
  });

  final Deck deck;
  final int added;
  final int merged;
}

/// [existing] with [back] appended as a new text block, or null when a line
/// of [existing] already holds [back] under the card key normalization.
List<Content>? mergeBack(List<Content> existing, String back) {
  final key = CardKey.fromFront(back);
  final lines = plainText(existing).split('\n').map(CardKey.fromFront);
  if (lines.contains(key)) return null;
  return [...existing, TextContent(back)];
}
