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

/// What a session over a selection would study now, as the domain that
/// studies decks counts it.
sealed class TodayCount {
  const TodayCount();
}

/// The count is being read.
final class TodayPending extends TodayCount {
  const TodayPending();
}

/// [review] cards are due and [fresh] cards are new.
final class TodayCounted extends TodayCount {
  const TodayCounted({required this.review, required this.fresh})
    : backlog = false;

  /// So many reviews are due that new cards pause until they are done.
  const TodayCounted.backlog({required this.review})
    : fresh = 0,
      backlog = true;

  final int review;
  final int fresh;

  /// Whether new cards pause for a backlog of reviews.
  final bool backlog;

  /// The size of the session: every due card and every new one.
  int get total => review + fresh;
}

/// The count could not be read; [message] says why, for the user.
final class TodayUnavailable extends TodayCount {
  const TodayUnavailable(this.message);

  final String message;
}

/// Builds what this domain shows of a [TodayCount].
typedef TodayBuilder = Widget Function(BuildContext context, TodayCount count);

/// Builds a widget that counts what a session over the decks would study now,
/// keeps the count current, and shows it through the given [TodayBuilder].
/// The composition site overrides it, as it does [studyScreenProvider].
final todayProvider =
    Provider<Widget Function(DeckSelection decks, TodayBuilder builder)>(
      (ref) => throw UnimplementedError(
        'todayProvider is overridden at the composition site',
      ),
    );

/// Builds the screen that adds cards from a photo to a deck, or creates a
/// deck from one when no deck is given; null while the app has none, which
/// hides the buttons that open it. The screen pops with the [Deck] it saved
/// into, or with nothing when the user left without saving.
final photoImportProvider = Provider<Widget Function(DeckId? deck)?>(
  (ref) => null,
);

/// Builds the account screen the deck list opens. The composition site
/// overrides it, so this domain does not depend on the one that holds
/// accounts.
final accountScreenProvider = Provider<Widget Function()>(
  (ref) => throw UnimplementedError(
    'accountScreenProvider is overridden at the composition site',
  ),
);

/// What the deck screens offer of sharing decks with other users: browsing
/// public decks, and publishing one of the user's own.
abstract interface class DeckSharing {
  /// Whether the device is online now, kept current. Publishing needs the
  /// network, so the deck menu disables it while offline.
  Stream<bool> watchOnline();

  /// The screen that browses other users' public decks.
  Widget browseScreen();

  /// Asks for what publishing [deck] needs and publishes it, reporting a
  /// failure to the user itself.
  Future<void> publish(BuildContext context, Deck deck);

  /// Makes [deck] private again, reporting a failure to the user itself.
  Future<void> unpublish(BuildContext context, Deck deck);
}

/// Sharing, or null while the app has none, which hides its entries. The
/// composition site overrides it, so this domain does not depend on the one
/// that shares decks.
final deckSharingProvider = Provider<DeckSharing?>((ref) => null);

/// Whether the device is online, as sharing reports it; offline without it.
final onlineProvider = StreamProvider.autoDispose<bool>(
  (ref) => ref.watch(deckSharingProvider)?.watchOnline() ?? Stream.value(false),
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
