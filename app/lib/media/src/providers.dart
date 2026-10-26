import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'audio.dart';
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

/// How stored audio is played: the device's player over the media store,
/// which a test replaces.
final audioPlaybackProvider = Provider<AudioPlayback>((ref) {
  final playback = DeviceAudioPlayback(ref.watch(mediaStoreProvider));
  ref.onDispose(playback.dispose);
  return playback;
});

/// How the user records audio: the device's microphone, which a test
/// replaces.
final audioRecordingProvider = Provider<AudioRecording>((ref) {
  final recording = DeviceAudioRecording();
  ref.onDispose(recording.dispose);
  return recording;
});

/// How the user picks an audio file: the device's file picker, which a test
/// replaces.
final audioPickProvider = Provider<AudioPick>((ref) => const DeviceAudioPick());
