import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:url_launcher/url_launcher.dart';

import 'failure.dart';
import 'photo.dart';

/// Which of a [PhotoSource]'s ways a photo is taken by.
enum PhotoOrigin {
  /// The system camera.
  camera,

  /// The photo library.
  album,
}

/// Where a photo comes from: the system camera, or the photo library.
abstract interface class PhotoSource {
  /// Lets the user take one photo with the system camera; null when they
  /// cancel. Throws [PhotoAccessDenied], [CameraUnavailable] or
  /// [PhotoUnreadable].
  Future<JpegPhoto?> takePhoto();

  /// Lets the user pick up to [limit] photos, in the order they picked them;
  /// null when they cancel. Each resolves to its photo, or throws
  /// [PhotoUnreadable] when it cannot be read, so one unreadable photo leaves
  /// the others. Throws [PhotoAccessDenied].
  Future<List<Future<JpegPhoto>>?> pickFromLibrary({int limit = 1});

  /// Opens this app's page in the system settings, where camera and photo
  /// access are allowed; false when it could not.
  Future<bool> openSettings();
}

/// The device's system camera and photo library through `image_picker`.
final class DevicePhotoSource implements PhotoSource {
  const DevicePhotoSource();

  /// The error codes `image_picker` reports for access the user or a
  /// restriction refused.
  static const _deniedCodes = {
    'camera_access_denied',
    'camera_access_restricted',
    'photo_access_denied',
    'photo_access_restricted',
  };

  @override
  Future<JpegPhoto?> takePhoto() async {
    final XFile? file;
    try {
      file = await ImagePicker().pickImage(
        source: ImageSource.camera,
        maxWidth: maxLongSide.toDouble(),
        maxHeight: maxLongSide.toDouble(),
        requestFullMetadata: false,
      );
    } on PlatformException catch (error) {
      throw _failureOf(error);
    }
    return file == null ? null : _prepare(file);
  }

  @override
  Future<List<Future<JpegPhoto>>?> pickFromLibrary({int limit = 1}) async {
    final List<XFile> files;
    try {
      files = await ImagePicker().pickMultiImage(
        maxWidth: maxLongSide.toDouble(),
        maxHeight: maxLongSide.toDouble(),
        limit: limit,
        requestFullMetadata: false,
      );
    } on PlatformException catch (error) {
      throw _failureOf(error);
    }
    return files.isEmpty ? null : [for (final file in files) _prepare(file)];
  }

  /// iOS's address of this app's settings page. Android never reports a
  /// refusal: the app declares no camera permission, so its camera intent
  /// and photo picker ask for none.
  @override
  Future<bool> openSettings() async {
    try {
      return await launchUrl(Uri.parse('app-settings:'));
    } on PlatformException {
      return false;
    }
  }

  static PhotoImportFailure _failureOf(PlatformException error) =>
      switch (error.code) {
        final code when _deniedCodes.contains(code) => PhotoAccessDenied(error),
        'no_available_camera' => CameraUnavailable(error),
        _ => PhotoUnreadable(error),
      };

  static Future<JpegPhoto> _prepare(XFile file) async =>
      preparePhoto(await file.readAsBytes());
}
