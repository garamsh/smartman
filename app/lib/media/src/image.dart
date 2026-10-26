import 'dart:isolate';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:image/image.dart' as img;

import 'failure.dart';
import 'model.dart';

/// The JPEG quality a stored image is encoded at.
const _quality = 85;

/// [cropImage] on a background isolate, so decoding a camera photo does not
/// stall the frame.
Future<PreparedImage> prepareImage(Uint8List encoded) =>
    Isolate.run(() => cropImage(encoded));

/// Decodes [encoded], applies its EXIF orientation, crops the centred square
/// a tile shows, scales it to at most [maxImageSide] on a side, and encodes it
/// as JPEG. Throws [MediaUnreadable] for bytes no decoder reads.
PreparedImage cropImage(Uint8List encoded) {
  final img.Image? decoded;
  try {
    decoded = img.decodeImage(encoded);
  } on Exception catch (cause) {
    throw MediaUnreadable(cause);
  }
  if (decoded == null) {
    throw const MediaUnreadable('no decoder reads the image');
  }
  final upright = img.bakeOrientation(decoded);
  final side = min(upright.width, upright.height);
  final square = img.copyCrop(
    upright,
    x: (upright.width - side) ~/ 2,
    y: (upright.height - side) ~/ 2,
    width: side,
    height: side,
  );
  final scaled = side <= maxImageSide
      ? square
      : img.copyResize(
          square,
          width: maxImageSide,
          height: maxImageSide,
          interpolation: img.Interpolation.average,
        );
  final bytes = img.encodeJpg(scaled, quality: _quality);
  return PreparedImage(bytes, sha256.convert(bytes).toString());
}
