import 'dart:isolate';
import 'dart:math';
import 'dart:typed_data';

import 'package:image/image.dart' as img;

import 'failure.dart';

/// The longest side, in pixels, of a photo sent for extraction.
const maxLongSide = 2048;

/// The largest image, in bytes, `extract-cards` accepts.
const maxPhotoBytes = 6 * 1024 * 1024;

/// The JPEG qualities tried in turn until the photo fits [maxPhotoBytes].
const _qualities = [85, 70, 55, 40];

/// A photo ready to send: upright, at most [maxLongSide] on its long side,
/// and JPEG-encoded in at most [maxPhotoBytes].
final class JpegPhoto {
  const JpegPhoto._(this.bytes, this.width, this.height);

  /// A photo prepared earlier and kept on the device, read back.
  const JpegPhoto.stored(this.bytes, this.width, this.height);

  final Uint8List bytes;
  final int width;
  final int height;
}

/// [downscalePhoto] on a background isolate, so decoding a camera photo does
/// not stall the frame.
Future<JpegPhoto> preparePhoto(Uint8List encoded) =>
    Isolate.run(() => downscalePhoto(encoded));

/// Decodes [encoded], applies its EXIF orientation, scales it so its long side
/// is at most [maxLongSide] keeping its aspect ratio, and encodes it as JPEG
/// under [maxPhotoBytes]. Throws [PhotoUnreadable] for bytes no decoder reads,
/// and [PhotoRefused] when even the lowest quality is too large.
JpegPhoto downscalePhoto(Uint8List encoded) {
  final img.Image? decoded;
  try {
    decoded = img.decodeImage(encoded);
  } on Exception catch (cause) {
    throw PhotoUnreadable(cause);
  }
  if (decoded == null) {
    throw const PhotoUnreadable('no decoder reads the image');
  }
  final upright = img.bakeOrientation(decoded);
  final longSide = max(upright.width, upright.height);
  final scaled = longSide <= maxLongSide
      ? upright
      : img.copyResize(
          upright,
          width: upright.width >= upright.height ? maxLongSide : null,
          height: upright.width < upright.height ? maxLongSide : null,
          interpolation: img.Interpolation.average,
        );
  for (final quality in _qualities) {
    final bytes = img.encodeJpg(scaled, quality: quality);
    if (bytes.length <= maxPhotoBytes) {
      return JpegPhoto._(bytes, scaled.width, scaled.height);
    }
  }
  throw const PhotoRefused(413);
}
