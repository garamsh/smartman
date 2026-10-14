import 'dart:convert';

/// A typed block of card content. Only text exists now; a new kind adds a
/// subclass and a discriminator value, and stored rows keep their encoding.
sealed class Content {
  const Content();
}

/// A block of plain text.
final class TextContent extends Content {
  const TextContent(this.text);

  final String text;

  @override
  bool operator ==(Object other) => other is TextContent && other.text == text;

  @override
  int get hashCode => text.hashCode;
}

/// A stored block whose type this version of the app does not know, kept
/// intact so saving the card again does not lose it.
final class UnsupportedContent extends Content {
  const UnsupportedContent(this.type, this.payload);

  final String type;
  final Object? payload;
}

const _textType = 'text';

/// Encodes [blocks] as a JSON array of `{type, payload}` objects.
String encodeContent(List<Content> blocks) => jsonEncode([
  for (final block in blocks)
    switch (block) {
      TextContent(:final text) => {
        'type': _textType,
        'payload': {'text': text},
      },
      UnsupportedContent(:final type, :final payload) => {
        'type': type,
        'payload': payload,
      },
    },
]);

/// Decodes what [encodeContent] wrote. An unknown `type` becomes
/// [UnsupportedContent]; input that is not that shape at all throws
/// [FormatException].
List<Content> decodeContent(String encoded) {
  final decoded = jsonDecode(encoded);
  if (decoded is! List<Object?>) {
    throw FormatException('content is not a list', encoded);
  }
  return [for (final block in decoded) _decodeBlock(block, encoded)];
}

Content _decodeBlock(Object? block, String source) {
  if (block is! Map<String, Object?>) {
    throw FormatException('content block is not an object', source);
  }
  final type = block['type'];
  final payload = block['payload'];
  if (type is! String) {
    throw FormatException('content block has no string type', source);
  }
  if (type != _textType) {
    return UnsupportedContent(type, payload);
  }
  if (payload is Map<String, Object?>) {
    final text = payload['text'];
    if (text is String) {
      return TextContent(text);
    }
  }
  throw FormatException('text block has no string text', source);
}

/// The text of [blocks]' text blocks, joined by newlines.
String plainText(List<Content> blocks) =>
    blocks.whereType<TextContent>().map((block) => block.text).join('\n');
