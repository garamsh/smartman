import 'dart:typed_data';

/// A stored file's id, a UUID the device makes. Decks and cards name a file
/// by it, never by a URL, so where the bytes live can change (ADR 0107).
extension type const MediaId(String value) {}

/// What a stored file holds.
enum MediaKind {
  image('image'),
  audio('audio');

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

/// The shape an image is stored in.
enum ImageShape {
  /// Its centred square, as a deck's tile shows it.
  square,

  /// Whole, at its own aspect ratio, as a card's image block shows it.
  whole,
}

/// An image made ready to store: in its [ImageShape], scaled to at most
/// [maxImageSide] on a side, and encoded as JPEG.
final class PreparedImage {
  const PreparedImage(
    this.bytes,
    this.sha256, {
    required this.width,
    required this.height,
  });

  final Uint8List bytes;

  /// [bytes]' SHA-256 digest, in lowercase hex.
  final String sha256;

  /// The encoded image's size in pixels, upright.
  final int width;
  final int height;
}

/// The longest side, in pixels, of a stored image.
const maxImageSide = 1024;

/// A recording or an audio file made ready to store: AAC in an MPEG-4
/// container, as both phones record it, or MP3, as a picked file may be
/// (ADR 0112).
final class PreparedAudio {
  const PreparedAudio(
    this.bytes,
    this.sha256, {
    required this.mimeType,
    required this.duration,
  });

  final Uint8List bytes;

  /// [bytes]' SHA-256 digest, in lowercase hex.
  final String sha256;

  /// `audio/mp4` or `audio/mpeg`, the types the bucket accepts.
  final String mimeType;

  /// How long it plays.
  final Duration duration;
}

/// The longest a stored recording or audio file may play.
const maxAudioDuration = Duration(seconds: 60);

/// The most bytes a stored audio file may hold, below the bucket's 10 MiB
/// ceiling.
const maxAudioBytes = 5 * 1024 * 1024;
