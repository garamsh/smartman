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

  group('a whole image (ADR 0109)', () {
    test('keeps its aspect ratio, scaled to the bound on its longer side, '
        'and states its size', () {
      final wide = fitImage(_png(3000, 1500));
      final tall = fitImage(_png(600, 1200));
      final small = fitImage(_png(300, 200));

      expect((wide.width, wide.height), (maxImageSide, maxImageSide ~/ 2));
      expect((tall.width, tall.height), (maxImageSide ~/ 2, maxImageSide));
      expect((small.width, small.height), (300, 200), reason: 'kept as is');
      for (final prepared in [wide, tall, small]) {
        final decoded = img.decodeJpg(prepared.bytes)!;
        expect(
          (decoded.width, decoded.height),
          (prepared.width, prepared.height),
        );
      }
      // Control: a tile's photo is cropped square from the same source.
      final square = cropImage(_png(3000, 1500));
      expect((square.width, square.height), (maxImageSide, maxImageSide));
    });

    test('a box in fractions of the image covers the same pixels at the '
        'size it was drawn on and the size it is stored at', () {
      // A 2000 by 1000 photo, white but for a green patch at (500, 200)
      // 400 by 300, which a box drawn on the full-size photo covers.
      final source = img.Image(width: 2000, height: 1000)
        ..clear(img.ColorRgb8(255, 255, 255));
      img.fillRect(
        source,
        x1: 500,
        y1: 200,
        x2: 900,
        y2: 500,
        color: img.ColorRgb8(0, 160, 0),
      );
      final box = (x: 500 / 2000, y: 200 / 1000, w: 400 / 2000, h: 300 / 1000);

      final stored = fitImage(img.encodePng(source));
      final decoded = img.decodeJpg(stored.bytes)!;
      expect((decoded.width, decoded.height), (1024, 512));

      bool green(img.Image image, num x, num y) {
        final pixel = image.getPixel(x.round(), y.round());
        return pixel.g > 120 && pixel.r < 80;
      }

      for (final image in [source, decoded]) {
        final (left, top) = (box.x * image.width, box.y * image.height);
        final (right, bottom) = (
          left + box.w * image.width,
          top + box.h * image.height,
        );
        // Inside each corner and at the centre of the box: the patch.
        for (final (x, y) in [
          (left + 4, top + 4),
          (right - 4, top + 4),
          (left + 4, bottom - 4),
          (right - 4, bottom - 4),
          ((left + right) / 2, (top + bottom) / 2),
        ]) {
          expect(green(image, x, y), isTrue, reason: '${image.width}: $x, $y');
        }
        // Control: just outside the box, the white around the patch.
        for (final (x, y) in [(left - 6, top + 4), (right + 6, bottom - 4)]) {
          expect(green(image, x, y), isFalse, reason: '${image.width}: $x, $y');
        }
      }
    });
  });
}
