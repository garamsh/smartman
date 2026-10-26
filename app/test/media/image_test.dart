import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:smartman/media/media.dart';
import 'package:smartman/media/src/image.dart';
import 'package:smartman/media/src/model.dart';

/// A PNG [width] by [height], white but for a red band 17 px wide at its
/// horizontal centre and a blue one at its left edge, wide enough to keep
/// their colour through JPEG.
Uint8List _png(int width, int height) {
  final image = img.Image(width: width, height: height)
    ..clear(img.ColorRgb8(255, 255, 255));
  for (var y = 0; y < height; y++) {
    for (var dx = -8; dx <= 8; dx++) {
      image
        ..setPixelRgb(width ~/ 2 + dx, y, 255, 0, 0)
        ..setPixelRgb(dx + 8, y, 0, 0, 255);
    }
  }
  return img.encodePng(image);
}

void main() {
  test('a wide image is cropped to its centred square, kept at its own size under the bound', () {
    final prepared = cropImage(_png(300, 200));
    final decoded = img.decodeJpg(prepared.bytes)!;

    expect((decoded.width, decoded.height), (200, 200));
    // The source's blue left edge falls outside the centred square, whose
    // left edge is white, and its red centre column stays at the centre.
    final left = decoded.getPixel(0, 100);
    expect(left.r, greaterThan(200), reason: 'white, not the blue edge');
    final centre = decoded.getPixel(100, 100);
    expect(centre.r, greaterThan(200));
    expect(centre.g, lessThan(60), reason: 'the red band');
  });

  test('a large image is cropped and scaled to the bound on each side', () {
    final prepared = cropImage(_png(3000, 2000));
    final decoded = img.decodeJpg(prepared.bytes)!;

    expect((decoded.width, decoded.height), (maxImageSide, maxImageSide));
  });

  test('the digest is the SHA-256 of the encoded bytes, in lowercase hex', () {
    final prepared = cropImage(_png(40, 40));

    expect(prepared.sha256, sha256.convert(prepared.bytes).toString());
    expect(prepared.sha256, matches(RegExp(r'^[0-9a-f]{64}$')));
  });

  test(
    'bytes no decoder reads are refused as unreadable, where an image is not',
    () {
      expect(
        () => cropImage(Uint8List.fromList([1, 2, 3, 4])),
        throwsA(isA<MediaUnreadable>()),
      );
      expect(cropImage(_png(40, 40)).bytes, isNotEmpty);
    },
  );
}
