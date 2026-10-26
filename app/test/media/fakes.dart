import 'dart:io';
import 'dart:typed_data';

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

/// A prepared image of [bytes], with a digest of the right shape.
PreparedImage preparedImage(List<int> bytes) =>
    PreparedImage(Uint8List.fromList(bytes), 'a' * 64);
