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

/// Builds the screen that studies the selected decks in one session. The
/// composition site overrides it, since the domain that studies decks depends
/// on this one.
final studyScreenProvider = Provider<Widget Function(DeckSelection decks)>(
  (ref) => throw UnimplementedError(
    'studyScreenProvider is overridden at the composition site',
  ),
);

/// Builds the deck list's header card: how many cards a session over every
/// deck in the selection would study today, and the action that starts it.
/// The composition site overrides it, as it does [studyScreenProvider].
final todayCardProvider = Provider<Widget Function(DeckSelection decks)>(
  (ref) => throw UnimplementedError(
    'todayCardProvider is overridden at the composition site',
  ),
);

/// Builds the account screen the deck list opens. The composition site
/// overrides it, so this domain does not depend on the one that holds
/// accounts.
final accountScreenProvider = Provider<Widget Function()>(
  (ref) => throw UnimplementedError(
    'accountScreenProvider is overridden at the composition site',
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
