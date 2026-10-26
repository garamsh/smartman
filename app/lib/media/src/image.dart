import 'dart:isolate';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:image/image.dart' as img;

import 'failure.dart';
import 'model.dart';

/// The JPEG quality a stored image is encoded at.
const _quality = 85;

/// [cropImage] or [fitImage], as [shape] asks, on a background isolate, so
/// decoding a camera photo does not stall the frame.
Future<PreparedImage> prepareImage(Uint8List encoded, ImageShape shape) =>
    Isolate.run(
      () => switch (shape) {
        ImageShape.square => cropImage(encoded),
        ImageShape.whole => fitImage(encoded),
      },
    );

/// Decodes [encoded], applies its EXIF orientation, crops the centred square
/// a tile shows, scales it to at most [maxImageSide] on a side, and encodes it
/// as JPEG. Throws [MediaUnreadable] for bytes no decoder reads.
PreparedImage cropImage(Uint8List encoded) {
  final upright = _upright(encoded);
  final side = min(upright.width, upright.height);
  return _encoded(
    img.copyCrop(
      upright,
      x: (upright.width - side) ~/ 2,
      y: (upright.height - side) ~/ 2,
      width: side,
      height: side,
    ),
  );
}

/// Decodes [encoded], applies its EXIF orientation, scales it whole to at
/// most [maxImageSide] on its longer side, keeping its aspect ratio, and
/// encodes it as JPEG, so a box stored in fractions of the image covers the
/// same part of it at any size (ADR 0109). Throws [MediaUnreadable] for bytes
/// no decoder reads.
PreparedImage fitImage(Uint8List encoded) => _encoded(_upright(encoded));

/// [encoded] decoded, its EXIF orientation applied.
img.Image _upright(Uint8List encoded) {
  final img.Image? decoded;
  try {
    decoded = img.decodeImage(encoded);
  } on Exception catch (cause) {
    throw MediaUnreadable(cause);
  }
  if (decoded == null) {
    throw const MediaUnreadable('no decoder reads the image');
  }
  return img.bakeOrientation(decoded);
}

/// [image] scaled to at most [maxImageSide] on its longer side, keeping its
/// aspect ratio, and encoded.
PreparedImage _encoded(img.Image image) {
  final longer = max(image.width, image.height);
  final scaled = longer <= maxImageSide
      ? image
      : img.copyResize(
          image,
          width: (image.width * maxImageSide / longer).round(),
          height: (image.height * maxImageSide / longer).round(),
          interpolation: img.Interpolation.average,
        );
  final bytes = img.encodeJpg(scaled, quality: _quality);
  return PreparedImage(
    bytes,
    sha256.convert(bytes).toString(),
    width: scaled.width,
    height: scaled.height,
  );
}
