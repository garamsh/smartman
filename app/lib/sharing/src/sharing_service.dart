import 'package:flutter/material.dart';

import '../../account/account.dart';
import '../../deck/deck.dart';
import '../../l10n/app_localizations.dart';
import 'browse_screen.dart';
import 'failure.dart';
import 'failure_message.dart';
import 'model.dart';
import 'publish_sheet.dart';
import 'reachability.dart';
import 'server.dart';

/// How a copy saves into the user's decks.
sealed class CopyTarget {
  const CopyTarget();
}

/// Into a new deck named after the public one.
final class CopyIntoNewDeck extends CopyTarget {
  const CopyIntoNewDeck();
}

/// Into the user's [deck], where each card whose key the deck already holds
/// does what [onDuplicate] says.
final class CopyIntoDeck extends CopyTarget {
  const CopyIntoDeck(this.deck, this.onDuplicate);

  final DeckId deck;
  final DuplicateChoice onDuplicate;
}

/// Sharing decks between users: browsing, previewing, copying, reporting and
/// blocking others' public decks, and publishing the user's own.
///
/// Every server call throws a [SharingFailure] on an expected failure, and
/// every local write a [DeckFailure].
class SharingService implements DeckSharing {
  SharingService({
    required this.server,
    required this.decks,
    required this.reachability,
    required this.clock,
  });

  final SharingServer server;
  final DeckRepository decks;
  final Reachability reachability;
  final DateTime Function() clock;

  /// How many decks the listing shows.
  static const listLimit = 100;

  /// How many cards a preview shows.
  static const previewLimit = 20;

  @override
  Stream<bool> watchOnline() => reachability.watchOnline();

  @override
  Widget browseScreen() => BrowseScreen(sharing: this);

  @override
  Future<void> publish(BuildContext context, Deck deck) =>
      showPublishSheet(context, sharing: this, deck: deck);

  @override
  Future<void> unpublish(BuildContext context, Deck deck) async {
    final messenger = ScaffoldMessenger.of(context);
    final l10n = AppLocalizations.of(context);
    final message = await describing(l10n, () async {
      await makePrivate(deck.id);
      return l10n.unpublished;
    });
    messenger.showSnackBar(SnackBar(content: Text(message)));
  }

  Future<List<PublicDeckSummary>> listDecks(String search, BrowseSort sort) =>
      server.listDecks(search: search.trim(), sort: sort, limit: listLimit);

  Future<List<PublicCard>> preview(DeckId deck) =>
      server.listCards(deck, limit: previewLimit);

  /// Copies every card of [deck] into the user's decks as [target] says, as
  /// ordinary cards that record where they came from. Refused with
  /// [DeckNoLongerPublic] once the deck is no longer public.
  Future<CardsImported> copy(PublicDeckSummary deck, CopyTarget target) async {
    final cards = await server.listCards(deck.id);
    if (!await server.recordImport(deck.id)) throw const DeckNoLongerPublic();
    final onDuplicate = switch (target) {
      CopyIntoNewDeck() => DuplicateChoice.addNew,
      CopyIntoDeck(:final onDuplicate) => onDuplicate,
    };
    return decks.importCards(
      switch (target) {
        CopyIntoNewDeck() => ImportIntoNewDeck(deck.name),
        CopyIntoDeck(:final deck) => ImportIntoDeck(deck),
      },
      [
        for (final card in cards)
          ImportedCard(
            front: plainText(card.front),
            back: plainText(card.back),
            onDuplicate: onDuplicate,
          ),
      ],
      source: FromPublicDeck(deck.id),
    );
  }

  Future<ReportOutcome> report(DeckId deck, ReportReason reason) =>
      server.report(deck, reason);

  Future<void> block(UserId user) => server.block(user);

  Future<DisplayName?> displayName() => server.displayName();

  /// Publishes the deck [id] on the server, then on the device, so a publish
  /// the server did not take is not left on the device for sync to push.
  /// Sets the user's display name first when [name] is given.
  Future<void> makePublic(
    DeckId id, {
    DisplayName? name,
    String? description,
  }) async {
    if (name != null) await server.setDisplayName(name);
    final deck = await decks.getDeck(id);
    final at = clock();
    final visibility = PublicDeck(at);
    await server.writeVisibility(
      deck,
      visibility,
      description: description,
      at: at,
    );
    await decks.setVisibility(id, visibility, description: description);
  }

  /// Makes the deck [id] private on the server, then on the device.
  Future<void> makePrivate(DeckId id) async {
    final deck = await decks.getDeck(id);
    const visibility = PrivateDeck();
    await server.writeVisibility(deck, visibility, at: clock());
    await decks.setVisibility(id, visibility);
  }
}

/// Runs [action] and returns its message, or the message for the sharing or
/// deck failure it raised. Any other exception propagates.
Future<String> describing(
  AppLocalizations l10n,
  Future<String> Function() action,
) async {
  try {
    return await action();
  } on SharingFailure catch (failure) {
    return describeSharingFailure(l10n, failure);
  } on DeckFailure catch (failure) {
    return describeFailure(l10n, failure);
  }
}
