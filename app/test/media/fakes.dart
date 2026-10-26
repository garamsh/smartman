import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:image/image.dart' as img;
import 'package:smartman/media/media.dart';

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

  @override
  Future<Uint8List?> download(MediaId id) async {
    _reach();
    return files[id];
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

  @override
  Future<PreparedImage?> pick(
    ImageOrigin origin, {
    ImageShape shape = ImageShape.square,
  }) async {
    picks.add((origin, shape));
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
    Directory.systemTemp.createTempSync('smartman_media_');

Future<void> deleteMediaDirectory(Directory directory) async {
  if (await directory.exists()) await directory.delete(recursive: true);
}

/// Where an app a test composes keeps images it never stores; nothing
/// creates it.
final unusedMediaDirectory = Directory(
  '${Directory.systemTemp.path}/smartman_media_unused',
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
