import 'dart:convert';

import 'package:http/http.dart' as http;

import 'failure.dart';
import 'photo.dart';

/// The most characters (code points) a card's topic has.
const maxTopicLength = 60;

/// A card the model read off the page, before the user reviews it: its
/// headword or question, its fullest answer, the part of speech the page
/// prints, and the topic of the page it belongs to.
final class CandidateCard {
  const CandidateCard({
    required this.front,
    required this.answer,
    this.partOfSpeech,
    this.topic,
  });

  final String front;

  /// The fullest answer the page supports.
  final String answer;

  /// The page's own notation, such as "[동]"; null when it prints none.
  final String? partOfSpeech;

  /// The part of the page the card comes from, such as "모음조화"; null from
  /// a function that names none.
  final String? topic;

  /// The answer as Review shows and saves it: the part of speech and a space
  /// before [answer] when the page prints one.
  String get back => switch (partOfSpeech) {
    final partOfSpeech? => '$partOfSpeech $answer',
    null => answer,
  };
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

/// A card of non-empty `front` and `back`. Its answer is its `answer`, else
/// its `meaning`, else, from a function deployed before the fields, its
/// `back`; with the optional `partOfSpeech` and a `topic` of 1 to
/// [maxTopicLength] characters. Other fields are not read.
CandidateCard _parseCard(Object? card) {
  if (card
      case final Map<String, Object?> fields &&
          {'front': final String front, 'back': final String back}
      when front.trim().isNotEmpty && back.trim().isNotEmpty) {
    String? optional(String key) =>
        fields.containsKey(key) ? _text(fields[key]) : null;
    final topic = optional('topic');
    if (topic != null && topic.runes.length > maxTopicLength) {
      throw const ServiceFailed("a card's topic is too long");
    }
    return CandidateCard(
      front: front.trim(),
      answer: optional('answer') ?? optional('meaning') ?? back.trim(),
      partOfSpeech: optional('partOfSpeech'),
      topic: topic,
    );
  }
  throw const ServiceFailed('a card is not two non-empty sides');
}

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
