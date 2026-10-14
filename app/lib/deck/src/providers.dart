import 'package:flutter/widgets.dart';
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

/// Builds the screen that studies a deck. The composition site overrides it,
/// since the domain that studies decks depends on this one.
final studyScreenProvider = Provider<Widget Function(Deck deck)>(
  (ref) => throw UnimplementedError(
    'studyScreenProvider is overridden at the composition site',
  ),
);

/// Every deck, kept current.
final decksProvider = StreamProvider.autoDispose<List<Deck>>(
  (ref) => ref.watch(deckRepositoryProvider).watchDecks(),
);

/// The cards of one deck, kept current.
final cardsProvider = StreamProvider.autoDispose.family<List<Card>, DeckId>(
  (ref, deckId) => ref.watch(deckRepositoryProvider).watchCards(deckId),
);
