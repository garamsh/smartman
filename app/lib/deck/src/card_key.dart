import 'package:unorm_dart/unorm_dart.dart' as unorm;

final _whitespaceRun = RegExp(r'\s+');

/// A card's front normalized for duplicate detection within a deck.
extension type const CardKey._(String value) {
  /// Normalizes [front]: NFKC, trim, collapse whitespace runs to one space,
  /// then case-fold. Punctuation and accents are kept.
  factory CardKey.fromFront(String front) {
    final composed = unorm.nfkc(front);
    final trimmed = composed.trim();
    final collapsed = trimmed.replaceAll(_whitespaceRun, ' ');
    // Simple case folding, as Dart's lowercase mapping provides it.
    return CardKey._(collapsed.toLowerCase());
  }

  /// Wraps a key read back from storage, where it was stored already normalized.
  const CardKey.stored(String value) : this._(value);
}
