import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../media/media.dart';

/// Stops the sound that plays, if any. A player no card started is not made
/// just to be stopped.
void stopSound(ProviderContainer providers) {
  if (providers.exists(audioPlaybackProvider)) {
    unawaited(providers.read(audioPlaybackProvider).stop());
  }
}
