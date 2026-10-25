import '../../deck/deck.dart';
import 'extraction_client.dart';

/// [card] as JSON, which [decodeCandidate] reads back, for a job's state kept
/// on the device.
Map<String, Object?> encodeCandidate(CandidateCard card) => {
  'front': card.front,
  'answer': card.answer,
  'topic': card.topic,
  'kind': card.kind.name,
  'type': card.type.name,
  if (card.senses.isNotEmpty)
    'senses': encodeContent([SensesContent(card.senses)]),
  if (card.extras.isNotEmpty)
    'extras': [
      for (final extra in card.extras)
        {'label': extra.label, 'text': extra.text},
    ],
  'pronunciation': ?card.pronunciation,
  if (card.examples.isNotEmpty) 'examples': card.examples,
  if (card.wholeFront case final blocks?) 'wholeFront': encodeContent(blocks),
};

/// The card [json] holds, as [encodeCandidate] wrote it; null for anything
/// else, since the state on the device may come from another build.
CandidateCard? decodeCandidate(Object? json) {
  if (json case {
    'front': final String front,
    'answer': final String answer,
    'topic': final String topic,
    'kind': final String kind,
    'type': final String type,
  }) {
    final cardKind = CardKind.values.asNameMap()[kind];
    final cardType = CardType.values.asNameMap()[type];
    final senses = switch (json['senses']) {
      null => const <CardSense>[],
      final String encoded => switch (decodeContent(encoded)) {
        [SensesContent(:final senses)] => senses,
        _ => null,
      },
      _ => null,
    };
    final extras = switch (json['extras']) {
      null => const <Extra>[],
      final List<Object?> extras => _extras(extras),
      _ => null,
    };
    final examples = switch (json['examples']) {
      null => const <String>[],
      final List<Object?> examples when examples.every((e) => e is String) =>
        examples.cast<String>(),
      _ => null,
    };
    final wholeFront = switch (json['wholeFront']) {
      null => null,
      final String encoded => decodeContent(encoded),
      _ => const <Content>[],
    };
    final (pronunciation, pronunciationRead) = switch (json['pronunciation']) {
      null => (null, true),
      final String text => (text, true),
      _ => (null, false),
    };
    if (cardKind == null ||
        cardType == null ||
        senses == null ||
        extras == null ||
        examples == null ||
        (wholeFront != null && wholeFront.isEmpty) ||
        !pronunciationRead) {
      return null;
    }
    return CandidateCard(
      front: front,
      answer: answer,
      topic: topic,
      kind: cardKind,
      type: cardType,
      senses: senses,
      extras: extras,
      pronunciation: pronunciation,
      examples: examples,
      wholeFront: wholeFront,
    );
  }
  return null;
}

List<Extra>? _extras(List<Object?> extras) {
  final read = <Extra>[];
  for (final extra in extras) {
    if (extra case {'label': final String label, 'text': final String text}) {
      read.add(Extra(label: label, text: text));
    } else {
      return null;
    }
  }
  return read;
}
