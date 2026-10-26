import 'dart:typed_data';

import 'failure.dart';
import 'model.dart';

/// Where the signed-in user's media is stored. Each method throws
/// [MediaTransferFailed] when the server cannot be reached or refuses.
abstract interface class MediaServer {
  /// Stores [upload]'s row, then [bytes] as its file; a row or file already
  /// stored, by an earlier attempt that lost its answer, counts as stored.
  Future<void> upload(MediaUpload upload, Uint8List bytes);

  /// The file of [id]; null when the server holds none.
  Future<Uint8List?> download(MediaId id);

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
  Future<Uint8List?> download(MediaId id) async => throw _refusal;

  @override
  Future<void> delete(MediaId id) async => throw _refusal;
}
