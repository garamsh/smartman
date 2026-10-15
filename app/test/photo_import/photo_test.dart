import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:smartman/photo_import/photo_import.dart';
import 'package:smartman/photo_import/src/photo.dart';

/// A [width] × [height] image of seeded noise, the hardest case for JPEG, so
/// the size limit is tested on the largest output a photo can make.
img.Image _noise(int width, int height) {
  final random = Random(7);
  final image = img.Image(width: width, height: height);
  for (final pixel in image) {
    pixel
      ..r = random.nextInt(256)
      ..g = random.nextInt(256)
      ..b = random.nextInt(256);
  }
  return image;
}

void main() {
  test('a large photo is scaled to the long side limit, keeping its aspect ratio, under the size limit', () {
    final source = _noise(4032, 3024);
    final encoded = img.encodePng(source);
    expect(encoded.length, greaterThan(maxPhotoBytes));

    final photo = downscalePhoto(encoded);

    expect((photo.width, photo.height), (2048, 1536));
    expect(photo.width / photo.height, closeTo(4032 / 3024, 0.001));
    expect(photo.bytes.length, lessThanOrEqualTo(maxPhotoBytes));
    final decoded = img.decodeJpg(photo.bytes)!;
    expect((decoded.width, decoded.height), (2048, 1536));
  });

  test('a portrait photo is scaled by its height', () {
    final photo = downscalePhoto(img.encodeJpg(_noise(1500, 3000)));

    expect((photo.width, photo.height), (1024, 2048));
  });

  test('a photo within the limit keeps its size', () {
    final photo = downscalePhoto(img.encodePng(_noise(800, 600)));

    expect((photo.width, photo.height), (800, 600));
    expect(img.decodeJpg(photo.bytes), isNotNull);
  });

  test('the EXIF orientation is applied before scaling, in JPEG and WebP', () {
    for (final encode in [img.encodeJpg, img.encodeWebP]) {
      final source = _noise(3000, 1000)..exif.imageIfd.orientation = 6;
      final encoded = encode(source);
      // Setup: the encoded file still carries the orientation.
      expect(img.decodeImage(encoded), isNotNull);

      final photo = downscalePhoto(encoded);

      // Orientation 6 rotates a quarter turn: the wide source stands upright.
      expect((photo.width, photo.height), (683, 2048), reason: '$encode');
    }
  });

  test('bytes no decoder reads are an unreadable photo', () {
    expect(
      () => downscalePhoto(Uint8List.fromList(List.filled(64, 7))),
      throwsA(isA<PhotoUnreadable>()),
    );
  });
}
