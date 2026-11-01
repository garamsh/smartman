import 'card_frame.dart';
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

/// Cards read from a spreadsheet's rows, stored as [CardSource.import].
final class FromFile extends AddSource {
  const FromFile();
}

/// Cards copied from another user's public deck [origin], stored as
/// [CardSource.copy] with that origin, their photos and sounds copied from
/// [owner]'s media as the user's own (ADR 0113).
final class FromCopy extends AddSource {
  const FromCopy(this.origin, {required this.owner});

  final DeckId origin;

  /// The id of the user who owns [origin], whose media folder holds its
  /// cards' files.
  final String owner;
}

/// What an incoming card does when a card in its deck already has its key.
enum DuplicateChoice {
  /// Writes nothing.
  skip,

  /// Appends the incoming back to the existing card's back on a new line,
  /// unless that back already holds it, as [mergeBack] says.
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
    this.cells,
    required this.onDuplicate,
  });

  /// A card of [cells], its sides their projection.
  factory IncomingCard.framed(
    List<Cell> cells, {
    required DuplicateChoice onDuplicate,
  }) {
    final (:front, :back) = sidesOf(cells);
    return IncomingCard(
      front: front,
      back: back,
      cells: cells,
      onDuplicate: onDuplicate,
    );
  }

  final List<Content> front;
  final List<Content> back;

  /// The 칸 of a framed card, written in the frame; [front] and [back] are
  /// then their projection.
  final List<Cell>? cells;
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

/// [existing] with [back] appended as a new text block, or null when [back]
/// is empty, or when under the card key normalization a line of [existing]
/// holds it or each of its lines is held, as a back of several lines is once
/// merged.
List<Content>? mergeBack(List<Content> existing, String back) {
  if (back.trim().isEmpty) return null;
  final lines = plainText(existing).split('\n').map(CardKey.fromFront).toSet();
  if (lines.contains(CardKey.fromFront(back)) ||
      back.split('\n').map(CardKey.fromFront).every(lines.contains)) {
    return null;
  }
  return [...existing, TextContent(back)];
}
