import 'dart:convert';

import 'package:http/http.dart' as http;

import 'failure.dart';
import 'photo.dart';

/// The most characters (code points) a card's topic has.
const maxTopicChars = 60;

/// What a card was read from: an entry of a vocabulary page, or a point of
/// notes.
enum CardKind { vocabulary, note }

/// What a card asks: a named concept and its statement, a line with one blank
/// and what fills it, or a printed sentence with a word to judge.
enum CardType { concept, cloze, identify }

/// One meaning of a vocabulary entry, with the part-of-speech label the page
/// prints for it, such as "[동]"; null when it prints none.
final class Sense {
  const Sense({this.pos, required this.meaning});

  final String? pos;
  final String meaning;

  @override
  bool operator ==(Object other) =>
      other is Sense && other.pos == pos && other.meaning == meaning;

  @override
  int get hashCode => Object.hash(pos, meaning);
}

/// Something else the page prints for a vocabulary entry, under its own
/// label, such as 유의어.
final class Extra {
  const Extra({required this.label, required this.text});

  final String label;
  final String text;
}

/// A card the model read off the page, before the user reviews it: its
/// headword or concept, the topic of the page it belongs to, and the fields of
/// its kind. A vocabulary card has its [senses] in page order, and [extras]
/// and a [pronunciation] when the page prints them; a note has its [answer].
final class CandidateCard {
  const CandidateCard({
    required this.front,
    this.answer = '',
    this.kind = CardKind.note,
    this.type = CardType.concept,
    this.senses = const [],
    this.extras = const [],
    this.pronunciation,
    this.examples = const [],
    this.topic,
  });

  /// A vocabulary card of one sense, as a function before senses sent it.
  CandidateCard.word({
    required String front,
    required String meaning,
    String? partOfSpeech,
    List<String> examples = const [],
    String? topic,
  }) : this(
         front: front,
         answer: meaning,
         kind: CardKind.vocabulary,
         senses: [Sense(pos: partOfSpeech, meaning: meaning)],
         examples: examples,
         topic: topic,
       );

  final String front;

  /// A note's answer; on a vocabulary card, the answer the function composed
  /// from its senses.
  final String answer;

  final CardKind kind;
  final CardType type;
  final List<Sense> senses;
  final List<Extra> extras;
  final String? pronunciation;

  /// The examples the page prints for the card; empty when it prints none.
  final List<String> examples;

  /// The part of the page the card comes from, such as "모음조화"; null from
  /// a function that names none.
  final String? topic;
}

/// Sends a photo to `extract-cards` and returns the cards it found.
abstract interface class ExtractionClient {
  /// The cards on [photo]'s page, or null once [cancel] completes before the
  /// answer arrives. Throws a [PhotoImportFailure] for each refusal.
  Future<List<CandidateCard>?> extract(
    JpegPhoto photo, {
    required Future<void> cancel,
  });
}

/// Calls the deployed function over HTTP with the signed-in user's token.
final class HttpExtractionClient implements ExtractionClient {
  HttpExtractionClient(
    this._http, {
    required this.functionUrl,
    required this.accessToken,
  });

  final http.Client _http;

  /// The function's URL, `<supabase url>/functions/v1/extract-cards`.
  final Uri functionUrl;

  /// The current session's access token, or null when signed out.
  final Future<String?> Function() accessToken;

  @override
  Future<List<CandidateCard>?> extract(
    JpegPhoto photo, {
    required Future<void> cancel,
  }) async {
    final token = await accessToken();
    if (token == null) throw const SignInRequired();
    final request = http.AbortableRequest(
      'POST',
      functionUrl,
      abortTrigger: cancel,
    );
    request.headers['authorization'] = 'Bearer $token';
    request.headers['content-type'] = 'application/json';
    request.body = jsonEncode({'image': base64Encode(photo.bytes)});
    final http.Response response;
    try {
      response = await http.Response.fromStream(await _http.send(request));
    } on http.RequestAbortedException {
      return null;
    } on http.ClientException catch (cause) {
      throw ExtractionOffline(cause);
    }
    return parseExtraction(response.statusCode, response.body);
  }
}

/// The cards a `200` [body] holds, or the failure [status] means, per the
/// contract in `docs/architecture/ai-extraction.md`.
List<CandidateCard> parseExtraction(int status, String body) =>
    switch (status) {
      200 => _parseCards(body),
      401 => throw const SignInRequired(),
      413 || 415 => throw PhotoRefused(status),
      422 => throw const NoCardsFound(),
      429 => throw const DailyLimitReached(),
      502 => throw const ModelFailed(),
      _ => throw ServiceFailed('HTTP $status'),
    };

List<CandidateCard> _parseCards(String body) {
  final Object? decoded;
  try {
    decoded = jsonDecode(body);
  } on FormatException {
    throw const ServiceFailed('the success body is not JSON');
  }
  if (decoded case {'cards': final List<Object?> cards} when cards.isNotEmpty) {
    return [for (final card in cards) _parseCard(card)];
  }
  throw const ServiceFailed('the success body holds no card list');
}

/// A card of non-empty `front` and `back`, a `topic` of 1 to
/// [maxTopicChars] characters when it has one, and the fields of its `kind`.
/// A note's answer is its `answer`, else its `back`. A vocabulary card's
/// senses are its `senses` of `{pos, meaning}`, else, from a function before
/// senses, one sense of its `meaning` or `answer`, else its `back`, with its
/// `partOfSpeech`. A card with no `kind` from a function before kinds is a
/// vocabulary card; one with no `type` is a concept. Other fields are not
/// read.
CandidateCard _parseCard(Object? card) {
  if (card
      case final Map<String, Object?> fields &&
          {'front': final String front, 'back': final String back}
      when front.trim().isNotEmpty && back.trim().isNotEmpty) {
    String? optional(String key) =>
        fields.containsKey(key) ? _text(fields[key]) : null;
    List<T> list<T>(String key, T Function(Object?) parse) =>
        switch (fields[key]) {
          null => const [],
          final List<Object?> items => [for (final item in items) parse(item)],
          _ => throw ServiceFailed('$key is not a list'),
        };
    final topic = optional('topic');
    if (topic != null && topic.runes.length > maxTopicChars) {
      throw const ServiceFailed("a card's topic is too long");
    }
    final kind = switch (fields['kind']) {
      'note' => CardKind.note,
      'vocabulary' || null => CardKind.vocabulary,
      _ => throw const ServiceFailed('a card has an unknown kind'),
    };
    final type = switch (fields['type']) {
      null => CardType.concept,
      final String name =>
        CardType.values.where((type) => type.name == name).firstOrNull ??
            (throw const ServiceFailed('a card has an unknown type')),
      _ => throw const ServiceFailed('a card has an unknown type'),
    };
    final answer = optional('answer') ?? optional('meaning') ?? back.trim();
    final senses = fields.containsKey('senses')
        ? list('senses', _parseSense)
        : [Sense(pos: optional('partOfSpeech'), meaning: answer)];
    if (kind == CardKind.vocabulary && senses.isEmpty) {
      throw const ServiceFailed('a vocabulary card has no sense');
    }
    return CandidateCard(
      front: front.trim(),
      answer: answer,
      kind: kind,
      type: type,
      senses: kind == CardKind.vocabulary ? senses : const [],
      extras: list('extras', _parseExtra),
      pronunciation: optional('pronunciation'),
      examples: list('examples', _text),
      topic: topic,
    );
  }
  throw const ServiceFailed('a card is not two non-empty sides');
}

Sense _parseSense(Object? sense) {
  if (sense case final Map<String, Object?> fields
      when fields.containsKey('meaning')) {
    final pos = fields['pos'];
    return Sense(
      pos: pos == null ? null : _text(pos),
      meaning: _text(fields['meaning']),
    );
  }
  throw const ServiceFailed('a sense has no meaning');
}

Extra _parseExtra(Object? extra) => switch (extra) {
  {'label': final Object? label, 'text': final Object? text} => Extra(
    label: _text(label),
    text: _text(text),
  ),
  _ => throw const ServiceFailed('an extra is not a label and a text'),
};

String _text(Object? value) => switch (value) {
  final String text when text.trim().isNotEmpty => text.trim(),
  _ => throw const ServiceFailed('a card field is not non-empty text'),
};

/// The URL of `extract-cards` for the project whose PostgREST URL is
/// [restUrl]. The Supabase client builds both as `<project url>/rest/v1` and
/// `<project url>/functions/v1`, so the suffix is swapped. Throws
/// [ArgumentError] for a URL without that suffix.
Uri extractCardsUrl(String restUrl) {
  const rest = '/rest/v1';
  if (!restUrl.endsWith(rest)) {
    throw ArgumentError.value(restUrl, 'restUrl', 'does not end in $rest');
  }
  final project = restUrl.substring(0, restUrl.length - rest.length);
  return Uri.parse('$project/functions/v1/extract-cards');
}
