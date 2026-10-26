import 'dart:typed_data';

import 'failure.dart';
import 'model.dart';

/// Where the signed-in user's media is stored. Each method throws
/// [MediaTransferFailed] when the server cannot be reached or refuses.
abstract interface class MediaServer {
  /// Stores [upload]'s row, then [bytes] as its file; the user's own row or
  /// file already stored under the id, by an earlier attempt that lost its
  /// answer, counts as stored. Another user's id is no conflict: a row's key
  /// is its owner and its id.
  Future<void> upload(MediaUpload upload, Uint8List bytes);

  /// The file of [id] in [owner]'s folder, the signed-in user's without one;
  /// null when the server holds none or does not let the user read it.
  /// Another user's file is read to copy it (ADR 0113).
  Future<Uint8List?> download(MediaId id, {String? owner});

  /// Deletes the file of [id], then its row; either already gone counts as
  /// deleted.
  Future<void> delete(MediaId id);
}

/// The server of a build whose configuration cannot sign anyone in: every
/// request fails, so the files stay on the device.
final class UnavailableMediaServer implements MediaServer {
  const UnavailableMediaServer();

  static const _refusal = MediaTransferFailed('this build cannot sign in');

  @override
  Future<void> upload(MediaUpload upload, Uint8List bytes) async =>
      throw _refusal;

  @override
  Future<Uint8List?> download(MediaId id, {String? owner}) async =>
      throw _refusal;

  @override
  Future<void> delete(MediaId id) async => throw _refusal;
}
