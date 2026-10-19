import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'content.dart';
import 'failure.dart';
import 'model.dart';

/// The form a card is written in: a front and a back of text, a word with its
/// senses, or a line with blanks (ADR 0083).
enum CardKind { basic, word, cloze }

/// The kind [card] is edited in: a cloze when its front holds one, a word when
/// its back holds senses, and otherwise basic.
CardKind kindOf(Card card) => card.front.any((block) => block is ClozeContent)
    ? CardKind.cloze
    : card.back.any((block) => block is SensesContent)
    ? CardKind.word
    : CardKind.basic;

const _cardKindsKey = 'deckCardKinds';

/// The keys [deckStorageProvider] must be opened to cache.
const deckStorageKeys = {_cardKindsKey};

/// The device storage the card editor keeps each deck's last kind in. The
/// composition site overrides it with the storage it opens, which caches
/// [deckStorageKeys].
final deckStorageProvider = Provider<SharedPreferencesWithCache>(
  (ref) => throw UnimplementedError(
    'deckStorageProvider is overridden at the composition site',
  ),
);

/// The kind a new card of [deck] starts in: the kind its last card was added
/// in, or basic when none was, or when the stored value cannot be read.
CardKind rememberedKind(SharedPreferencesWithCache storage, DeckId deck) {
  final kinds = _kinds(storage);
  return CardKind.values.asNameMap()[kinds[deck.value]] ?? CardKind.basic;
}

/// Remembers [kind] as the kind [deck]'s next new card starts in; a write the
/// device refuses is a [StorageFailure].
Future<void> rememberKind(
  SharedPreferencesWithCache storage,
  DeckId deck,
  CardKind kind,
) async {
  try {
    await storage.setString(
      _cardKindsKey,
      jsonEncode({..._kinds(storage), deck.value: kind.name}),
    );
  } on Exception catch (cause) {
    throw StorageFailure(cause);
  }
}

/// The stored kinds by deck id; empty when none are stored or the value is
/// not a JSON object of strings.
Map<String, String> _kinds(SharedPreferencesWithCache storage) {
  final stored = storage.getString(_cardKindsKey);
  if (stored == null) return {};
  try {
    final decoded = jsonDecode(stored);
    return decoded is Map<String, Object?>
        ? {
            for (final MapEntry(:key, :value) in decoded.entries)
              if (value is String) key: value,
          }
        : {};
  } on FormatException {
    return {};
  }
}
