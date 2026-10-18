import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../deck/deck.dart';
import '../../l10n/app_localizations.dart';
import '../../photo_import/photo_import.dart';
import '../../sharing/sharing.dart';
import 'deck_screen.dart';
import 'option_sheet.dart';

enum _NewDeck { manual, photo, public }

/// Offers the ways to start a deck the app has: by hand, from a photo, and
/// from a public deck; then starts the one chosen.
Future<void> showNewDeckSheet(BuildContext context, WidgetRef ref) async {
  final l10n = AppLocalizations.of(context);
  final photoImport = ref.read(photoImportProvider);
  final sharing = ref.read(sharingServiceProvider);
  final choice = await showOptionSheet(
    context,
    title: l10n.newDeckTitle,
    options: [
      (
        icon: LucideIcons.pencilLine,
        title: l10n.createManually,
        body: l10n.createManuallyBody,
        value: _NewDeck.manual,
      ),
      if (photoImport != null)
        (
          icon: LucideIcons.camera,
          title: l10n.createFromPhoto,
          body: l10n.createFromPhotoBody,
          value: _NewDeck.photo,
        ),
      if (sharing != null)
        (
          icon: LucideIcons.compass,
          title: l10n.importFromPublic,
          body: l10n.importFromPublicBody,
          value: _NewDeck.public,
        ),
    ],
  );
  if (!context.mounted) return;
  switch (choice) {
    case _NewDeck.manual:
      await createDeckByHand(context, ref);
    case _NewDeck.photo when photoImport != null:
      await importDeckFromPhoto(context, photoImport);
    case _NewDeck.public when sharing != null:
      await Navigator.of(
        context,
      ).push(MaterialPageRoute<void>(builder: (_) => sharing.browseScreen()));
    case _NewDeck.photo || _NewDeck.public || null:
      return;
  }
}

/// Asks for a name and creates an empty deck with it.
Future<void> createDeckByHand(BuildContext context, WidgetRef ref) async {
  final repository = ref.read(deckRepositoryProvider);
  final l10n = AppLocalizations.of(context);
  final name = await showNameSheet(
    context,
    title: l10n.newDeckTitle,
    body: l10n.newDeckBody,
    action: l10n.create,
  );
  if (name == null || !context.mounted) return;
  await reportingFailure(context, () => repository.createDeck(name));
}

/// Starts photo import for a new deck, then opens the deck it saved into.
Future<void> importDeckFromPhoto(
  BuildContext context,
  PhotoImport photoImport,
) async {
  final navigator = Navigator.of(context);
  final deck = await photoImport(context, null);
  if (deck == null || !context.mounted) return;
  await navigator.push(
    MaterialPageRoute<void>(builder: (_) => DeckScreen(deck: deck)),
  );
}
