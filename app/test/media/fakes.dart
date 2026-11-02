import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:image/image.dart' as img;
import 'package:knowno/media/media.dart';

/// The media server in memory: one account's rows and files, by id. Shared
/// by two stores, it is that account on two devices.
class FakeMediaServer implements MediaServer {
  final rows = <MediaId, MediaUpload>{};
  final files = <MediaId, Uint8List>{};

  /// While true, every request fails as an unreachable server's does.
  bool offline = false;

  /// How many requests reached the server, failed ones included.
  int requests = 0;

  void _reach() {
    requests++;
    if (offline) throw const MediaTransferFailed('offline');
  }

  @override
  Future<void> upload(MediaUpload upload, Uint8List bytes) async {
    _reach();
    rows.putIfAbsent(upload.id, () => upload);
    files.putIfAbsent(upload.id, () => bytes);
  }

  /// Other users' files the account may read, by their owner and id.
  final shared = <(String, MediaId), Uint8List>{};

  /// How many more downloads of each id fail as an unreachable server's do
  /// before one is answered.
  final failingDownloads = <MediaId, int>{};

  @override
  Future<Uint8List?> download(MediaId id, {String? owner}) async {
    _reach();
    if (failingDownloads[id] case final failures? when failures > 0) {
      failingDownloads[id] = failures - 1;
      throw const MediaTransferFailed('lost');
    }
    return owner == null ? files[id] : shared[(owner, id)];
  }

  @override
  Future<void> delete(MediaId id) async {
    _reach();
    files.remove(id);
    rows.remove(id);
  }
}

/// Hands out [next] on each pick, recording the origin and shape asked for.
class FakeImagePick implements ImagePick {
  PreparedImage? next;
  final picks = <(ImageOrigin, ImageShape)>[];

  /// While set, a pick returns once it completes, as a picker the user is
  /// still in does.
  Completer<void>? hold;

  @override
  Future<PreparedImage?> pick(
    ImageOrigin origin, {
    ImageShape shape = ImageShape.square,
  }) async {
    picks.add((origin, shape));
    await hold?.future;
    return next;
  }
}

/// A whole JPEG [width] by [height], prepared as a card's photo is.
PreparedImage preparedWholeImage(int width, int height) {
  final bytes = img.encodeJpg(
    img.Image(width: width, height: height)..clear(img.ColorRgb8(0, 120, 200)),
  );
  return PreparedImage(
    bytes,
    sha256.convert(bytes).toString(),
    width: width,
    height: height,
  );
}

/// A new, empty directory under the system's temporary one, deleted by
/// [deleteMediaDirectory].
Directory newMediaDirectory() =>
    Directory.systemTemp.createTempSync('knowno_media_');

Future<void> deleteMediaDirectory(Directory directory) async {
  if (await directory.exists()) await directory.delete(recursive: true);
}

/// Where an app a test composes keeps images it never stores; nothing
/// creates it.
final unusedMediaDirectory = Directory(
  '${Directory.systemTemp.path}/knowno_media_unused',
);

/// A 4 px JPEG, prepared, of one red, 40 times [shade] modulo 256, so the
/// images of nearby shades differ.
PreparedImage preparedImage(int shade) {
  final bytes = img.encodeJpg(
    img.Image(width: 4, height: 4)
      ..clear(img.ColorRgb8(shade * 40 % 256, 0, 0)),
  );
  return PreparedImage(
    bytes,
    sha256.convert(bytes).toString(),
    width: 4,
    height: 4,
  );
}

/// A player that plays nothing, recording each id asked for in [plays].
class FakeAudioPlayback implements AudioPlayback {
  final plays = <MediaId>[];

  /// What each play answers: whether the file could be played.
  bool playable = true;

  /// How many times playback was stopped.
  int stops = 0;

  /// Whether a sound plays now: started by a play that could play it, and
  /// not stopped since.
  bool playing = false;

  @override
  Future<bool> play(MediaId id) async {
    plays.add(id);
    playing = playable;
    return playable;
  }

  @override
  Future<void> stop() async {
    stops++;
    playing = false;
  }
}

/// A recorder that hands out [next] when stopped, or throws [failure] when
/// started, counting each call.
class FakeAudioRecording implements AudioRecording {
  PreparedAudio? next;
  MediaFailure? failure;
  int starts = 0;
  int stops = 0;
  int cancels = 0;

  @override
  Future<void> start() async {
    starts++;
    if (failure case final failure?) throw failure;
  }

  @override
  Future<PreparedAudio?> stop() async {
    stops++;
    return next;
  }

  @override
  Future<void> cancel() async => cancels++;
}

/// A file picker that hands out [next], or throws [failure].
class FakeAudioPick implements AudioPick {
  PreparedAudio? next;
  MediaFailure? failure;

  @override
  Future<PreparedAudio?> pick() async {
    if (failure case final failure?) throw failure;
    return next;
  }
}

/// A few bytes standing for a recording of [milliseconds], prepared as a
/// recorded sound is.
PreparedAudio preparedAudio(int milliseconds) => prepareAudio(
  Uint8List.fromList(List.filled(64, milliseconds % 256)),
  mimeType: 'audio/mp4',
  duration: Duration(milliseconds: milliseconds),
);

/// The first bytes of an MPEG-4 file, its `ftyp` box, then [fill], standing
/// for a recorded sound as it reaches the server.
Uint8List mp4Bytes(int fill) => Uint8List.fromList([
  0, 0, 0, 0x18, 0x66, 0x74, 0x79, 0x70, 0x4D, 0x34, 0x41, 0x20, //
  ...List.filled(20, fill),
]);

/// The first bytes of an MP3 file with an ID3 tag, then [fill].
Uint8List mp3Bytes(int fill) => Uint8List.fromList([
  0x49, 0x44, 0x33, 4, 0, //
  ...List.filled(20, fill),
]);
