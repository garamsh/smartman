import 'card_key.dart';
import 'content.dart';

/// Identifies a deck.
extension type const DeckId(String value) {}

/// Identifies a card.
extension type const CardId(String value) {}

/// A named collection of cards.
final class Deck {
  const Deck({
    required this.id,
    required this.name,
    required this.createdAt,
    required this.updatedAt,
  });

  final DeckId id;
  final String name;
  final DateTime createdAt;
  final DateTime updatedAt;
}

/// Where a card came from. Only [manual] is created now; [import] is
/// reserved for photo import.
enum CardSource { manual, import }

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
  });

  final CardId id;
  final DeckId deckId;
  final List<Content> front;
  final List<Content> back;
  final CardKey cardKey;
  final CardSource source;
  final DateTime createdAt;
  final DateTime updatedAt;
}
