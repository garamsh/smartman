import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/painting.dart';

import 'failure.dart';

/// Where a photo import job keeps its prepared photos and its state on the
/// device, so a job outlives its screen and a closed app can resume it.
abstract interface class ImportJobStore {
  /// Keeps [jpeg] and resolves to the key it is read back by. Throws
  /// [PhotoNotKept] when it cannot be written.
  Future<String> putPhoto(Uint8List jpeg);

  /// The photo kept under [key]. Throws [PhotoNotKept] when it cannot be
  /// read, as when its file is gone.
  Future<Uint8List> photo(String key);

  /// The photo kept under [key], for drawing at most [width] logical pixels
  /// wide, so a thumbnail decodes no more than it draws.
  ImageProvider image(String key, {int? width});

  /// The job's state as [writeState] last wrote it; null when none is kept.
  Future<String?> readState();

  Future<void> writeState(String state);

  /// Forgets the state and every photo.
  Future<void> clear();
}

/// An [ImportJobStore] in [directory]: each photo a JPEG file, the state one
/// JSON file beside them.
final class FileImportJobStore implements ImportJobStore {
  FileImportJobStore(this.directory);

  final Directory directory;

  var _next = 0;

  File get _state => File('${directory.path}/job.json');

  File _file(String key) => File('${directory.path}/$key');

  @override
  Future<String> putPhoto(Uint8List jpeg) async {
    try {
      await directory.create(recursive: true);
      late String key;
      do {
        key = '${DateTime.now().microsecondsSinceEpoch}-${_next++}.jpg';
      } while (await _file(key).exists());
      await _file(key).writeAsBytes(jpeg, flush: true);
      return key;
    } on FileSystemException catch (cause) {
      throw PhotoNotKept(cause);
    }
  }

  @override
  Future<Uint8List> photo(String key) async {
    try {
      return await _file(key).readAsBytes();
    } on FileSystemException catch (cause) {
      throw PhotoNotKept(cause);
    }
  }

  @override
  ImageProvider image(String key, {int? width}) =>
      ResizeImage.resizeIfNeeded(width, null, FileImage(_file(key)));

  @override
  Future<String?> readState() async =>
      await _state.exists() ? _state.readAsString() : null;

  @override
  Future<void> writeState(String state) async {
    await directory.create(recursive: true);
    final next = File('${directory.path}/job.json.next');
    await next.writeAsString(state, flush: true);
    await next.rename(_state.path);
  }

  @override
  Future<void> clear() async {
    if (await directory.exists()) await directory.delete(recursive: true);
  }
}
