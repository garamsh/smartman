import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'content.dart';
import 'failure.dart';
import 'label_presets.dart';
import 'model.dart';

/// The form a card is written in: a front and a back of one meaning or of
/// senses, a line with blanks, a table with blanks (ADR 0100), or each side
/// a list of blocks of any type (ADR 0108). Each is a template a card
/// records, which only decides how the editor opens it (ADR 0106).
enum CardKind {
  basic('flip'),
  cloze('cloze'),
  table('table'),
  free('free');

  const CardKind(this.template);

  /// The `template` a card written in this kind records: `flip` for 앞뒤.
  final String template;
}

/// The version of every template this build writes.
const cardTemplateVersion = 1;

/// The kind a card whose front is [front] is read as when it records no
/// template: a cloze or a table when its front holds one, and otherwise
/// basic, its back's senses included.
CardKind derivedKind(List<Content> front) =>
    front.any((block) => block is ClozeContent)
    ? CardKind.cloze
    : front.any((block) => block is TableContent)
    ? CardKind.table
    : CardKind.basic;

/// The kind [card] is edited in: the one its template names, or
/// [derivedKind] while it records none; null for a template, or a template
/// version, this build does not know, which opens the card read-only.
CardKind? kindOf(Card card) => switch ((card.template, card.templateVersion)) {
  (null, _) => derivedKind(card.front),
  (_, final version?) when version > cardTemplateVersion => null,
  (final template?, _) =>
    CardKind.values.where((kind) => kind.template == template).firstOrNull,
};

const _cardKindsKey = 'deckCardKinds';

/// The keys [deckStorageProvider] must be opened to cache.
const deckStorageKeys = {_cardKindsKey, labelPresetsKey};

/// The device storage the card editor keeps each deck's last kind and the
/// label presets in. The composition site overrides it with the storage it
/// opens, which caches [deckStorageKeys].
final deckStorageProvider = Provider<SharedPreferencesWithCache>(
  (ref) => throw UnimplementedError(
    'deckStorageProvider is overridden at the composition site',
  ),
);

/// The kind a new card of [deck] starts in: the kind its last card was added
/// in, or basic when none was, when the stored value cannot be read, or when
/// it names the word kind ADR 0100 folded into basic.
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
