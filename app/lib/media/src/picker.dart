import 'dart:io';

import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';

import 'failure.dart';
import 'image.dart';
import 'model.dart';

/// Where a picked image comes from.
enum ImageOrigin {
  /// The system camera.
  camera,

  /// The photo library.
  album,
}

/// Lets the user pick one image, made ready to store.
abstract interface class ImagePick {
  /// The image picked, cropped and scaled by [prepareImage], or null when
  /// the user cancels. Throws [MediaUnreadable] when the camera or library
  /// cannot be opened or the image cannot be read.
  Future<PreparedImage?> pick(ImageOrigin origin);
}

/// The device's system camera and photo library through `image_picker`.
final class DeviceImagePick implements ImagePick {
  const DeviceImagePick();

  /// Twice a stored image's side, so the crop keeps detail without decoding
  /// a full camera frame.
  static const _pickSide = maxImageSide * 2.0;

  @override
  Future<PreparedImage?> pick(ImageOrigin origin) async {
    final Uint8List bytes;
    try {
      final file = await ImagePicker().pickImage(
        source: switch (origin) {
          ImageOrigin.camera => ImageSource.camera,
          ImageOrigin.album => ImageSource.gallery,
        },
        maxWidth: _pickSide,
        maxHeight: _pickSide,
        requestFullMetadata: false,
      );
      if (file == null) return null;
      bytes = await file.readAsBytes();
    } on PlatformException catch (cause) {
      throw MediaUnreadable(cause);
    } on IOException catch (cause) {
      throw MediaUnreadable(cause);
    }
    return prepareImage(bytes);
  }
}
