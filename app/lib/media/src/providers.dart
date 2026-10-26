import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'media_store.dart';
import 'picker.dart';

/// The media store. The composition site overrides it with the instance it
/// constructs.
final mediaStoreProvider = Provider<MediaStore>(
  (ref) => throw UnimplementedError(
    'mediaStoreProvider is overridden at the composition site',
  ),
);

/// How the user picks an image: the device's camera and photo library, which
/// a test replaces.
final imagePickProvider = Provider<ImagePick>((ref) => const DeviceImagePick());
