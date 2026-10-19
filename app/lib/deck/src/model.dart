import 'card_key.dart';
import 'content.dart';

/// Identifies a deck.
extension type const DeckId(String value) {}

/// Identifies a card.
extension type const CardId(String value) {}

/// One or more decks studied together; never empty.
final class DeckSelection {
  /// The selection of [first] and every deck in [rest].
  DeckSelection(DeckId first, [Iterable<DeckId> rest = const []])
    : ids = Set.unmodifiable({first, ...rest});

  final Set<DeckId> ids;

  /// The selection of [decks], or null when there is none.
  static DeckSelection? of(Iterable<DeckId> decks) =>
      decks.isEmpty ? null : DeckSelection(decks.first, decks.skip(1));
}

/// Whether other signed-in users can find a deck.
sealed class DeckVisibility {
  const DeckVisibility();
}

/// Only its owner sees the deck; the default.
final class PrivateDeck extends DeckVisibility {
  const PrivateDeck();
}

/// Others can find, preview and copy the deck, since [publishedAt].
final class PublicDeck extends DeckVisibility {
  const PublicDeck(this.publishedAt);

  final DateTime publishedAt;
}

/// A named collection of cards.
final class Deck {
  const Deck({
    required this.id,
    required this.name,
    required this.createdAt,
    required this.updatedAt,
    this.visibility = const PrivateDeck(),
    this.description,
  });

  final DeckId id;
  final String name;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DeckVisibility visibility;

  /// What the owner wrote about the deck when publishing it, if anything.
  final String? description;
}

/// Where a card came from: the editor writes [manual], photo import
/// [import], and a copy of another user's public deck [copy].
enum CardSource { manual, import, copy }

/// A card inside a deck.
final class Card {
  const Card({
    required this.id,
    required this.deckId,
    required this.front,
    required this.back,
    required this.cardKey,
    required this.source,
    required this.createdAt,
    required this.updatedAt,
    this.originDeckId,
  });

  final CardId id;
  final DeckId deckId;
  final List<Content> front;
  final List<Content> back;
  final CardKey cardKey;
  final CardSource source;
  final DateTime createdAt;
  final DateTime updatedAt;

  /// The public deck a [CardSource.copy] card was copied from; null for any
  /// other card.
  final DeckId? originDeckId;
}
