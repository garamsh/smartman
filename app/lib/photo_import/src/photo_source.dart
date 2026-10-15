import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';

import 'failure.dart';
import 'photo.dart';

/// Where a photo comes from: the camera, or the photo library.
abstract interface class PhotoSource {
  /// Opens the camera. Throws [CameraDenied] or [CameraUnavailable].
  Future<CameraSession> openCamera();

  /// Lets the user pick one photo; null when they cancel. Throws
  /// [PhotoUnreadable] for a file that is not an image this app reads.
  Future<JpegPhoto?> pickFromLibrary();
}

/// An open camera, until [close].
abstract interface class CameraSession {
  /// The live preview.
  Widget get preview;

  /// Takes a photo. Throws [CameraUnavailable] or [PhotoUnreadable].
  Future<JpegPhoto> takePicture();

  Future<void> close();
}

/// The device's back camera through `camera`, and its photo library through
/// `image_picker`.
final class DevicePhotoSource implements PhotoSource {
  const DevicePhotoSource();

  /// The error codes `camera` reports for access the user or a restriction
  /// refused.
  static const _deniedCodes = {
    'CameraAccessDenied',
    'CameraAccessDeniedWithoutPrompt',
    'CameraAccessRestricted',
  };

  @override
  Future<CameraSession> openCamera() async {
    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) {
        throw const CameraUnavailable('the device reports no camera');
      }
      final camera = cameras.firstWhere(
        (camera) => camera.lensDirection == CameraLensDirection.back,
        orElse: () => cameras.first,
      );
      final controller = CameraController(
        camera,
        ResolutionPreset.veryHigh,
        enableAudio: false,
      );
      try {
        await controller.initialize();
      } on CameraException {
        await controller.dispose();
        rethrow;
      }
      return _DeviceCamera(controller);
    } on CameraException catch (error) {
      throw _deniedCodes.contains(error.code)
          ? CameraDenied(error)
          : CameraUnavailable(error);
    }
  }

  @override
  Future<JpegPhoto?> pickFromLibrary() async {
    final XFile? file;
    try {
      file = await ImagePicker().pickImage(
        source: ImageSource.gallery,
        maxWidth: maxLongSide.toDouble(),
        maxHeight: maxLongSide.toDouble(),
        requestFullMetadata: false,
      );
    } on PlatformException catch (error) {
      throw PhotoUnreadable(error);
    }
    if (file == null) return null;
    return preparePhoto(await file.readAsBytes());
  }
}

final class _DeviceCamera implements CameraSession {
  _DeviceCamera(this._controller);

  final CameraController _controller;

  @override
  Widget get preview => CameraPreview(_controller);

  @override
  Future<JpegPhoto> takePicture() async {
    final XFile file;
    try {
      file = await _controller.takePicture();
    } on CameraException catch (error) {
      throw CameraUnavailable(error);
    }
    return preparePhoto(await file.readAsBytes());
  }

  @override
  Future<void> close() => _controller.dispose();
}
