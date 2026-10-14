import 'package:flutter_test/flutter_test.dart';
import 'package:smartman/deck/src/content.dart';

void main() {
  group('content encoding', () {
    test('round-trips a text block with its type discriminator', () {
      const blocks = [TextContent('bonjour')];

      final encoded = encodeContent(blocks);

      expect(encoded, '[{"type":"text","payload":{"text":"bonjour"}}]');
      expect(decodeContent(encoded), blocks);
    });

    test('decodes an unknown type as unsupported and re-encodes it intact', () {
      const stored =
          '[{"type":"text","payload":{"text":"cat"}},'
          '{"type":"image","payload":{"path":"cat.png"}}]';

      final blocks = decodeContent(stored);

      expect(blocks.first, const TextContent('cat'));
      final unsupported = blocks.last;
      expect(unsupported, isA<UnsupportedContent>());
      expect((unsupported as UnsupportedContent).type, 'image');
      expect(encodeContent(blocks), stored);
    });

    test('rejects a text block without text as a format error', () {
      expect(
        () => decodeContent('[{"type":"text","payload":{}}]'),
        throwsFormatException,
      );
    });
  });
}
