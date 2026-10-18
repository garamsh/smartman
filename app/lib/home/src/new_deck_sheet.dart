import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../deck/deck.dart';
import '../../l10n/app_localizations.dart';
import '../../photo_import/photo_import.dart';
import 'deck_screen.dart';
import 'option_sheet.dart';

/// A way to start a new deck: by hand, or from a photo taken or picked.
sealed class _NewDeck {
  const _NewDeck();
}

final class _ByHand extends _NewDeck {
  const _ByHand();
}

final class _FromPhoto extends _NewDeck {
  const _FromPhoto(this.origin);

  final PhotoOrigin origin;
}

/// Offers the ways to start a deck the app has: by hand, and, with photo
/// import, from a photo taken with the camera or picked from the album; then
/// starts the one chosen.
Future<void> showNewDeckSheet(BuildContext context, WidgetRef ref) async {
  final l10n = AppLocalizations.of(context);
  final photoImport = ref.read(photoImportProvider);
  final choice = await showOptionSheet<_NewDeck>(
    context,
    title: l10n.newDeckTitle,
    options: [
      (
        icon: LucideIcons.pencilLine,
        title: l10n.createManually,
        body: l10n.createManuallyBody,
        value: const _ByHand(),
      ),
      if (photoImport != null) ...[
        (
          icon: LucideIcons.camera,
          title: l10n.photoCamera,
          body: l10n.photoCameraBody,
          value: const _FromPhoto(PhotoOrigin.camera),
        ),
        (
          icon: LucideIcons.images,
          title: l10n.photoAlbum,
          body: l10n.photoAlbumBody,
          value: const _FromPhoto(PhotoOrigin.album),
        ),
      ],
    ],
  );
  if (!context.mounted) return;
  switch (choice) {
    case _ByHand():
      await createDeckByHand(context, ref);
    case _FromPhoto(:final origin) when photoImport != null:
      await importDeckFromPhoto(context, photoImport, origin);
    case _FromPhoto() || null:
      return;
  }
}

/// Asks for a name, creates an empty deck with it, and opens it, as a photo
/// import opens the deck it saved into.
Future<void> createDeckByHand(BuildContext context, WidgetRef ref) async {
  final repository = ref.read(deckRepositoryProvider);
  final navigator = Navigator.of(context);
  final l10n = AppLocalizations.of(context);
  final name = await showNameSheet(
    context,
    title: l10n.newDeck,
    body: l10n.newDeckBody,
    action: l10n.create,
  );
  if (name == null || !context.mounted) return;
  Deck? created;
  await reportingFailure(
    context,
    () async => created = await repository.createDeck(name),
  );
  if (created case final deck?) {
    await navigator.push(
      MaterialPageRoute<void>(builder: (_) => DeckScreen(deck: deck)),
    );
  }
}

/// Starts photo import for a new deck from a photo by [origin], then opens
/// the deck it saved into.
Future<void> importDeckFromPhoto(
  BuildContext context,
  PhotoImport photoImport,
  PhotoOrigin origin,
) async {
  final navigator = Navigator.of(context);
  final deck = await photoImport(context, null, origin);
  if (deck == null || !context.mounted) return;
  await navigator.push(
    MaterialPageRoute<void>(builder: (_) => DeckScreen(deck: deck)),
  );
}
