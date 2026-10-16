import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'deck_repository.dart';
import 'model.dart';

/// The deck repository. The composition site overrides it with the instance
/// it constructs.
final deckRepositoryProvider = Provider<DeckRepository>(
  (ref) => throw UnimplementedError(
    'deckRepositoryProvider is overridden at the composition site',
  ),
);

/// One deck, kept current; null once it is deleted.
final deckProvider = StreamProvider.autoDispose.family<Deck?, DeckId>(
  (ref, id) => ref.watch(deckRepositoryProvider).watchDeck(id),
);

/// How many cards each deck holds, kept current; a deck with none is absent.
final cardCountsProvider = StreamProvider.autoDispose<Map<DeckId, int>>(
  (ref) => ref.watch(deckRepositoryProvider).watchCardCounts(),
);

/// Every deck, kept current.
final decksProvider = StreamProvider.autoDispose<List<Deck>>(
  (ref) => ref.watch(deckRepositoryProvider).watchDecks(),
);

/// The cards of one deck, kept current.
final cardsProvider = StreamProvider.autoDispose.family<List<Card>, DeckId>(
  (ref, deckId) => ref.watch(deckRepositoryProvider).watchCards(deckId),
);
