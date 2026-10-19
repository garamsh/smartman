import 'card_key.dart';
import 'content.dart';
import 'model.dart';

/// The deck a batch of incoming cards is added to.
sealed class AddTarget {
  const AddTarget();
}

/// An existing deck.
final class AddToDeck extends AddTarget {
  const AddToDeck(this.deck);

  final DeckId deck;
}

/// A deck the batch creates, named [name].
final class AddToNewDeck extends AddTarget {
  const AddToNewDeck(this.name);

  final String name;
}

/// Where incoming cards come from, which their stored source records.
sealed class AddSource {
  const AddSource();
}

/// Cards read off a photo, stored as [CardSource.import].
final class FromPhoto extends AddSource {
  const FromPhoto();
}

/// Cards copied from another user's public deck [origin], stored as
/// [CardSource.copy] with that origin.
final class FromCopy extends AddSource {
  const FromCopy(this.origin);

  final DeckId origin;
}

/// What an incoming card does when a card in its deck already has its key.
enum DuplicateChoice {
  /// Writes nothing.
  skip,

  /// Appends the incoming back to the existing card's back on a new line,
  /// unless a line of that back already holds it.
  mergeBack,

  /// Adds the incoming card beside the existing one.
  addNew,
}

/// A card to add, its sides as content blocks, and what it does when its
/// key collides.
final class IncomingCard {
  const IncomingCard({
    required this.front,
    required this.back,
    required this.onDuplicate,
  });

  final List<Content> front;
  final List<Content> back;
  final DuplicateChoice onDuplicate;
}

/// What a batch wrote into [deck]: [added] new cards and [merged] backs.
final class CardsAdded {
  const CardsAdded({
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
