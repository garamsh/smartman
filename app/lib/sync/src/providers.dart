import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'sync_controller.dart';

/// The sync controller. The composition site overrides it with the one it
/// starts.
final syncControllerProvider = Provider<SyncController>(
  (ref) => throw UnimplementedError(
    'syncControllerProvider is overridden at the composition site',
  ),
);
