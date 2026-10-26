import 'dart:typed_data';

/// A stored file's id, a UUID the device makes. Decks and cards name a file
/// by it, never by a URL, so where the bytes live can change (ADR 0107).
extension type const MediaId(String value) {}

/// What a stored file holds; `audio` is reserved for a later card kind.
enum MediaKind {
  image('image');

  const MediaKind(this.key);

  /// The key the database and the server store.
  final String key;
}

/// A file waiting to be uploaded: its id and what the server's row records.
final class MediaUpload {
  const MediaUpload({
    required this.id,
    required this.kind,
    required this.mimeType,
    required this.byteSize,
    required this.sha256,
    required this.createdAt,
  });

  final MediaId id;
  final MediaKind kind;
  final String mimeType;
  final int byteSize;

  /// The file's SHA-256 digest, in lowercase hex.
  final String sha256;
  final DateTime createdAt;
}

/// An image made ready to store: cropped to a square, scaled to at most
/// [maxImageSide] on a side, and encoded as JPEG.
final class PreparedImage {
  const PreparedImage(this.bytes, this.sha256);

  final Uint8List bytes;

  /// [bytes]' SHA-256 digest, in lowercase hex.
  final String sha256;
}

/// The longest side, in pixels, of a stored image.
const maxImageSide = 1024;
