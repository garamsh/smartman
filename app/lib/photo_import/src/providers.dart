import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../deck/deck.dart';
import 'photo_source.dart';

/// Adds cards from a photo to [deck], or creates a deck from one when [deck]
/// is null, starting from the camera or the library, as [origin] names, over
/// [context]. Resolves to the [Deck] it saved into, or to null when the user
/// cancelled or left without saving.
typedef PhotoImport = Future<Deck?> Function(
  BuildContext context,
  DeckId? deck,
  PhotoOrigin origin,
);

/// The photo import; null while the app has no extraction client, which
/// hides the buttons that start it. The composition site overrides it when
/// it has a client.
final photoImportProvider = Provider<PhotoImport?>((ref) => null);
