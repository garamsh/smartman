import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../deck/deck.dart';

/// Builds the screen that adds cards from a photo to a deck, or creates a
/// deck from one when no deck is given; null while the app has no extraction
/// client, which hides the buttons that open it. The screen pops with the
/// [Deck] it saved into, or with nothing when the user left without saving.
/// The composition site overrides it when it has a client.
final photoImportProvider = Provider<Widget Function(DeckId? deck)?>(
  (ref) => null,
);
