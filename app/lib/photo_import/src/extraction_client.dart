import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../deck/deck.dart';
import 'failure.dart';
import 'photo.dart';

/// The most characters (code points) a card's topic has.
const maxTopicChars = 60;

/// What a card was read from: an entry of a vocabulary page, or a point of
/// notes.
enum CardKind { vocabulary, note }

/// What a card asks: a named concept and its statement, a line with blanks
/// and what fills each, a printed sentence with a word to judge, or a whole
/// table with the cells to recall as blanks.
enum CardType { concept, cloze, identify, table }

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
    this.wholeFront,
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
         senses: [_oneSense(partOfSpeech, meaning)],
         examples: examples,
         topic: topic,
       );

  final String front;

  /// A note's answer; on a vocabulary card, the answer the function composed
  /// from its senses.
  final String answer;

  final CardKind kind;
  final CardType type;
  final List<CardSense> senses;
  final List<Extra> extras;
  final String? pronunciation;

  /// The examples the page prints for the card; empty when it prints none.
  final List<String> examples;

  /// The part of the page the card comes from, such as "모음조화"; null from
  /// a function that names none.
  final String? topic;

  /// A table or cloze card's front as content blocks, drawn whole (ADR
  /// 0068): a cloze of [front] and its answers, or [front] as the table's
  /// name above its table. Null for every other card, and for a cloze card
  /// from a function that sends no `cloze`.
  final List<Content>? wholeFront;
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
      403 when _errorCode(body) == 'suspended' =>
        throw const AccountSuspendedFailure(),
      413 || 415 => throw PhotoRefused(status),
      422 => throw const NoCardsFound(),
      429 => throw DailyLimitReached(dailyLimit: _dailyLimit(body)),
      502 => throw const ModelFailed(),
      _ => throw ServiceFailed('HTTP $status'),
    };

/// The `error` code a refusal's [body] names, or null when it names none.
String? _errorCode(String body) {
  try {
    return switch (jsonDecode(body)) {
      {'error': final String code} => code,
      _ => null,
    };
  } on FormatException {
    return null;
  }
}

/// The daily limit a `429` [body] states, or null when it states none.
int? _dailyLimit(String body) {
  try {
    return switch (jsonDecode(body)) {
      {'daily_limit': final int limit} when limit >= 0 => limit,
      _ => null,
    };
  } on FormatException {
    return null;
  }
}

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
/// senses are its `senses`, each `{labels, meaning, examples}` as `deck`'s
/// [decodeSense] reads it (ADR 0075), else, from a function before senses,
/// one sense of its `meaning` or `answer`, else its `back`, its
/// `partOfSpeech` as a label as printed. A card with no `kind` from a function before kinds is a
/// vocabulary card; one with no `type`, or a `type` this version does not
/// know, is a concept, so a new type does not fail the extraction. A cloze
/// card's `cloze` and a table card's `table` become its [wholeFront]. Other
/// fields are not read.
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
      final String name =>
        CardType.values.where((type) => type.name == name).firstOrNull ??
            CardType.concept,
      _ => CardType.concept,
    };
    final answer = optional('answer') ?? optional('meaning') ?? back.trim();
    final senses = fields.containsKey('senses')
        ? list('senses', _parseSense)
        : [_oneSense(optional('partOfSpeech'), answer)];
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
      wholeFront: _wholeFront(type, front.trim(), fields),
    );
  }
  throw const ServiceFailed('a card is not two non-empty sides');
}

/// A cloze card's `cloze`, `{answers}`, as a cloze of [front], or a table
/// card's `table`, `{columns, rows, blanks}`, under [front] as its name; null
/// for any other card, or one without its field. The blocks' own decoding
/// checks their shape (`deck.md`).
List<Content>? _wholeFront(
  CardType type,
  String front,
  Map<String, Object?> fields,
) {
  final block = switch ((type, fields)) {
    (CardType.cloze, {'cloze': final Map<String, Object?> cloze}) => {
      'type': 'cloze',
      'payload': {'text': front, 'answers': cloze['answers']},
    },
    (CardType.table, {'table': final Map<String, Object?> table}) => {
      'type': 'table',
      'payload': table,
    },
    _ => null,
  };
  if (block == null) return null;
  final List<Content> decoded;
  try {
    decoded = decodeContent(jsonEncode([block]));
  } on FormatException {
    throw ServiceFailed("a card's ${type.name} is not one");
  }
  return [if (type == CardType.table) TextContent(front), ...decoded];
}

/// A function before senses: one sense of [meaning], with its part of speech
/// [label] when it gives one, without the brackets or parentheses around it:
/// a part of speech when it is one's short form, such as 동, else another
/// label as printed (ADR 0075).
CardSense _oneSense(String? label, String meaning) {
  final text = label?.replaceAll(RegExp(r'^[\[(]|[\])]$'), '');
  final category = PartOfSpeech.values
      .where((part) => part.short == text)
      .firstOrNull;
  return CardSense(
    labels: [
      if (category != null)
        PartOfSpeechLabel(category, text!)
      else if (text != null)
        OtherLabel(text),
    ],
    meaning: meaning,
  );
}

CardSense _parseSense(Object? sense) => switch (decodeSense(sense)) {
  final decoded? => CardSense(
    labels: decoded.labels,
    meaning: decoded.meaning.trim(),
    examples: [for (final example in decoded.examples) example.trim()],
  ),
  null => throw const ServiceFailed(
    'a sense is not {labels, meaning, examples}',
  ),
};

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
