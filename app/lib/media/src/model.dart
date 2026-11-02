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

/// Another user's file, copied onto the device under [id], a new media id of
/// the user's own, with what its upload's row records; not yet queued
/// (ADR 0113).
final class FetchedMedia {
  const FetchedMedia({
    required this.id,
    required this.kind,
    required this.mimeType,
    required this.byteSize,
    required this.sha256,
  });

  final MediaId id;
  final MediaKind kind;

  /// `image/jpeg`, `image/png`, `image/webp`, `audio/mp4` or `audio/mpeg`.
  final String mimeType;
  final int byteSize;

  /// The file's SHA-256 digest, in lowercase hex.
  final String sha256;
}

/// The kind and MIME type [bytes] open with, among the types the bucket
/// accepts: a JPEG, PNG or WebP image, the last two as an MCP card's photo is
/// stored (ADR 0144); an MPEG-4 file, or an ADTS AAC stream as a picked `.aac`
/// is stored; or an MP3. Null for any other bytes. The owner's row is not
/// readable, so a fetched file's type comes from its bytes (ADR 0113).
(MediaKind, String)? mediaTypeOf(Uint8List bytes) => switch (bytes) {
  [0xFF, 0xD8, 0xFF, ...] => (MediaKind.image, 'image/jpeg'),
  [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, ...] => (
    MediaKind.image,
    'image/png',
  ),
  [
    0x52,
    0x49,
    0x46,
    0x46, // RIFF
    _,
    _,
    _,
    _,
    0x57,
    0x45,
    0x42,
    0x50, // WEBP
    ...,
  ] =>
    (MediaKind.image, 'image/webp'),
  [_, _, _, _, 0x66, 0x74, 0x79, 0x70, ...] => (MediaKind.audio, 'audio/mp4'),
  // An ADTS header is a frame sync whose layer bits are 00.
  [0xFF, final second, ...] when second & 0xF6 == 0xF0 => (
    MediaKind.audio,
    'audio/mp4',
  ),
  [0x49, 0x44, 0x33, ...] => (MediaKind.audio, 'audio/mpeg'),
  // An MP3 without a tag opens on a frame sync whose layer is not 00.
  [0xFF, final second, ...] when second & 0xE0 == 0xE0 && second & 0x06 != 0 =>
    (MediaKind.audio, 'audio/mpeg'),
  _ => null,
};
