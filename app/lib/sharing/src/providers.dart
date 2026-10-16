import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'sharing_service.dart';

/// Sharing, or null while the app has none, which hides its entries. The
/// composition site overrides it with the service it constructs.
final sharingServiceProvider = Provider<SharingService?>((ref) => null);

/// Whether the device is online, as sharing reports it; offline without it.
final onlineProvider = StreamProvider.autoDispose<bool>(
  (ref) =>
      ref.watch(sharingServiceProvider)?.watchOnline() ?? Stream.value(false),
);
